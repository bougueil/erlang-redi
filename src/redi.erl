%%% -*- erlang -*-
%%%
%%% This file is part of erlang-redi released under the BSD license.
%%%
%%% Copyright (c) 2018 Renaud Mariana <rmariana@gmail.com>
%%%
-module(redi).
-behaviour(gen_server).

%% API
-export([start_link/0, start_link/1, start_link/2,
	 stop/1,
	 set/3, set/4,
	 get/2,
	 delete/2, size/1,
	 get_bucket_name/1, add_bucket/2, add_bucket/3,
	 dump/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3, format_status/2]).

-define(SERVER, ?MODULE).
-define(ts_ms(), erlang:system_time(milli_seconds)).
-define(ts_max,  16#7ffffffffffffff).
-define(ts_non_gc,  (?ts_max - 256)). %% 256 non gc ts values

%% default configuration values
-define(ENTRY_TTL, 3600000).     %% 1hour
-define(GC_INTERVAL_MS, 30000).
-define(BUCKET_NAME, redi_keys).
-define(BUCKET_TYPE, set).

-record(state, {next_gc_ms, entry_ttl_ms, bucket_name, gc}).




-spec start_link() -> {ok, Pid :: pid()} |
		      {error, Error :: {already_started, pid()}} |
		      {error, Error :: term()} |
		      ignore.
start_link() ->
    start_link(#{}).

-spec start_link(atom() | map() ) -> {ok, Pid :: pid()} |
		      {error, Error :: {already_started, pid()}} |
		      {error, Error :: term()} |
		      ignore.
start_link(Name) when is_atom(Name) ->
    start_link(Name, #{});
start_link(Opts) when is_map(Opts) ->
    start_link(?SERVER, Opts).

stop(Name) ->
      gen_server:stop(Name).

%% @doc creates an REDI cache 
%% Options are:
%%  - `bucket_name' name of the ets table (used by get)
%%  - `entry_ttl_ms' the time to live of REDI elements
%%  - `next_gc_ms' next interval time REDI will scan to remove oldest elements
%%

-spec start_link(atom(), map()) -> {ok, Pid :: pid()} |
		      {error, Error :: {already_started, pid()}} |
		      {error, Error :: term()} |
		      ignore.
start_link(Name, Opts) ->
    gen_server:start_link({local, Name}, ?MODULE, [Opts], []).

-spec delete(Gen_server :: pid(), Key :: term()) -> ok.
delete(Pid, Key) ->
    gen_server:call(Pid, {delete, Key}).

-spec get(Bucket_name :: atom(), Key :: term()) -> list().
get(Bucket_name, Key) ->
    ets:lookup(Bucket_name, Key).

-spec size(Bucket_name :: atom()) -> pos_integer().
size(Bucket_name) ->
    ets:info(Bucket_name, size).

-spec set(Gen_server :: pid(), Key :: term(), Value :: term()) -> ok.
set(Pid, Key, Value) ->
    gen_server:call(Pid, {set, Key, Value}).

-spec set(Gen_server :: pid(), Key :: term(), Value :: term(), Bucket_name ::atom()) -> ok.
set(Pid, Key, Value, Bucket_name) when is_atom(Bucket_name) ->
    case ets:info(Bucket_name) of
	undefined ->
	    {error, undefined_bucket};
	_ ->
	    gen_server:call(Pid, {set, Key, Value, Bucket_name})
    end.

%% @doc get bucket name. Default is redi_keys
%% the bucket name is required by get/2
-spec get_bucket_name(Gen_server :: pid()) -> atom().
get_bucket_name(Pid) ->
    gen_server:call(Pid, get_bucket_name).

dump(Pid) ->
    gen_server:call(Pid, dump).

add_bucket(Pid, Bucket_name) ->
   add_bucket(Pid, Bucket_name, ?BUCKET_TYPE).

add_bucket(Pid, Bucket_name, Bucket_type) ->
    gen_server:call(Pid, {add_bucket, Bucket_name, Bucket_type}).


%%====================================================================
%% Internal functions
%%====================================================================
%%

%% @private
-spec init(Args :: term()) -> {ok, State :: term()} |
			      {ok, State :: term(), Timeout :: timeout()} |
			      {ok, State :: term(), hibernate} |
			      {stop, Reason :: term()} |
			      ignore.
init([Opts]) ->
    process_flag(trap_exit, true),
    Bucket_name = maps:get(bucket_name, Opts, ?BUCKET_NAME),
    Bucket_type = maps:get(bucket_type, Opts, ?BUCKET_TYPE),
    Next_gc_ms = maps:get(next_gc_ms, Opts, ?GC_INTERVAL_MS),
    create_bucket(Bucket_name, Bucket_type),
    erlang:send_after(Next_gc_ms, self(), refresh_gc),
    {ok, #state{
	    next_gc_ms = Next_gc_ms,
	    bucket_name = Bucket_name,
	    entry_ttl_ms = maps:get(entry_ttl_ms, Opts, ?ENTRY_TTL),
	    gc = queue:new()}}.


%% @private
-spec handle_call(Request :: term(), From :: {pid(), term()}, State :: term()) ->
			 {reply, Reply :: term(), NewState :: term()} |
			 {reply, Reply :: term(), NewState :: term(), Timeout :: timeout()} |
			 {reply, Reply :: term(), NewState :: term(), hibernate} |
			 {noreply, NewState :: term()} |
			 {noreply, NewState :: term(), Timeout :: timeout()} |
			 {noreply, NewState :: term(), hibernate} |
			 {stop, Reason :: term(), Reply :: term(), NewState :: term()} |
			 {stop, Reason :: term(), NewState :: term()}.

handle_call({set, Key, Value}, _From, #state{gc=GC, bucket_name=Bucket_name}=State) ->
    NewGC = do_insert_gc(?ts_ms(), Key, GC),
    ets:insert(Bucket_name, {Key, Value}),
    {reply, ok, State#state{gc=NewGC}};

handle_call({set, Key, Value, Bucket_name}, _From, #state{gc=GC}=State) ->
    NewGC = do_insert_gc(?ts_ms(), Key, GC),
    ets:insert(Bucket_name, {Key, Value}),
    {reply, ok, State#state{gc=NewGC}};

handle_call(dump, _From, #state{gc=GC, bucket_name=Bucket_name}=State) ->
    {reply, {ets:tab2list(Bucket_name), queue:len(GC)}, State};

handle_call(get_bucket_name, _From, #state{bucket_name=Bucket_name}=State) ->
    {reply, Bucket_name, State};

handle_call({add_bucket, Bucket_name, Bucket_type}, _From, State) ->
    create_bucket(Bucket_name, Bucket_type),
    {reply, Bucket_name, State};

handle_call({delete, Key}, _From, #state{gc=GC, bucket_name=Bucket_name}=State) ->
    ets:delete(Bucket_name, Key),
    NewGC = queue:from_list(lists:keydelete(Key, 2, queue:to_list(GC))),
    {reply, ok,  State#state{gc=NewGC}}.


%% @private
-spec handle_cast(Request :: term(), State :: term()) ->
			 {noreply, NewState :: term()} |
			 {noreply, NewState :: term(), Timeout :: timeout()} |
			 {noreply, NewState :: term(), hibernate} |
			 {stop, Reason :: term(), NewState :: term()}.
handle_cast(_Request, State) ->
    {noreply, State}.


%% @private
-spec handle_info(Info :: timeout() | term(), State :: term()) ->
			 {noreply, NewState :: term()} |
			 {noreply, NewState :: term(), Timeout :: timeout()} |
			 {noreply, NewState :: term(), hibernate} |
			 {stop, Reason :: normal | term(), NewState :: term()}.
handle_info(refresh_gc, #state{entry_ttl_ms=TTL}=State) ->
    T_gc_ms = ?ts_ms() - TTL,
    State2 = clean_older0(T_gc_ms, State),
    erlang:send_after(State#state.next_gc_ms, self(), refresh_gc),
{noreply, State2}.

%% @private
-spec terminate(Reason :: normal | shutdown | {shutdown, term()} | term(),
		State :: term()) -> any().
terminate(_Reason, _State) ->
    ok.

%% @private
-spec code_change(OldVsn :: term() | {down, term()},
		  State :: term(),
		  Extra :: term()) -> {ok, NewState :: term()} |
				      {error, Reason :: term()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

-spec format_status(Opt :: normal | terminate,
		    Status :: list()) -> Status :: term().
format_status(_Opt, Status) ->
    Status.


do_insert_gc(Ts, Key, GC) when Ts  <  ?ts_non_gc ->
    queue:in({Ts,Key}, GC);
do_insert_gc(_Ts, _Key, GC) -> GC.

clean_older0(T_gc_ms, State) ->

    case queue:peek(State#state.gc) of
	empty ->
	    State;
	{value, _V ={Ts, Key}} when Ts < T_gc_ms ->
	    ets:delete(State#state.bucket_name, Key),
	    GC1 = queue:drop(State#state.gc),
	    clean_older0(T_gc_ms, State#state{gc = GC1});
	{value, _V}  ->
	    State
    end.



create_bucket(Bucket_name, Bucket_type) ->
    ets:new(Bucket_name, [Bucket_type, named_table, {read_concurrency, true}]).


-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

redi_test() ->
    Bucket_name = test,
    TTL = 500,
    {ok, Pid} = redi:start_link(#{bucket_name => Bucket_name,
				  next_gc_ms => 100,
				  entry_ttl_ms=> TTL}),
    redi:set(Pid, <<"aaa">>, {<<"data.aaa1">>, #{}, #{}}), 
    redi:set(Pid, <<"aaa">>, {<<"data.aaa2">>, #{}, #{}}), 
    redi:set(Pid, <<"bbb">>, {<<"data.aaa">>, #{}, #{}}),

    redi:set(Pid, <<"ccc">>, {<<"data.ccc1">>, #{}, #{}}), 
    redi:set(Pid, <<"ccc">>, {<<"data.ccc2">>, #{}, #{}}), 
    redi:set(Pid, <<"ddd">>, {<<"data.ccc">>, #{}, #{}}),
    [{<<"aaa">>, {<<"data.aaa2">>, #{}, #{}}}] = redi:get(Bucket_name, <<"aaa">>),
    redi:delete(Pid, <<"aaa">>), 

    ?assertEqual(redi:get(Bucket_name, <<"aaa">>), []),
    ?assertEqual(redi:size(Bucket_name), 3),

    %% data expires after TTL
     timer:sleep(TTL+100),
    ?assertEqual(redi:size(Bucket_name), 0),
    ?assertEqual(redi:get(Bucket_name, <<"aaa">>), []),

    %% multi buckets
    redi:add_bucket(Pid, another_bucket, bag),
    redi:set(Pid, <<"aaa">>, <<"data.aaay">>, another_bucket),
    ?assertEqual(redi:get(another_bucket, <<"aaa">>), [{<<"aaa">>,<<"data.aaay">>}]),
    redi:stop(Pid).

heavy_test() ->
    Pid_name = heavy_redi,
    Bucket_name = test,
    {ok, _Pid} = redi:start_link(Pid_name,
				#{bucket_name => Bucket_name,
				  next_gc_ms => 10000,
				  entry_ttl_ms=> 30000}),
    N = 200000,
    Fun_writes = fun() ->
		     [redi:set(Pid_name, <<I:40>>, {<<"data.", <<I:40>>/binary >>})
		      || I <- lists:seq(1, N)]
	     end,
    Fun_reads = fun() ->
		    [redi:get(Bucket_name, <<I:40>>) || I <- lists:seq(1, N)]
	    end,

    {Twrite, _} = timer:tc(Fun_writes),
    ?debugFmt("throughput ~p writes/s.", [N * 1000000 div Twrite]),
    {Tread, _} = timer:tc(Fun_reads),
    ?debugFmt("throughput ~p reads/s.", [N * 1000000 div Tread]),
    redi:stop(Pid_name).
-endif.
