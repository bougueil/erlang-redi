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
	 stop/1, child_spec/1, child_spec/2,
	 set/3, set/4,
	 set_bulk/3, set_bulk/4,
	 get/2,
	 delete/2, size/1,
	 get_bucket_name/1, add_bucket/2, add_bucket/3,
	 gc_client/2, gc_client/3,
	 all/1, dump/1,
	 get_maybe_update/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3, format_status/2]).

-define(SERVER, ?MODULE).
-define(ts_ms(), erlang:system_time(milli_seconds)).
-define(ts_max,  16#7ffffffffffffff).
-define(ts_non_gc,  (?ts_max - 256)). %% 256 non gc ts values

%% default configuration values
-define(ENTRY_TTL_MS, timer:hours(1)).
-define(GC_INTERVAL_MS, timer:seconds(30)).
-define(BUCKET_NAME, redi_keys).
-define(BUCKET_TYPE, set).

-record(state, {next_gc_ms, entry_ttl_ms, bucket_name, gc_q, gc_client}).




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
%%  - `bucket_type' type of bucket, default to 'set'
%%  - `entry_ttl_ms' the time to live of REDI elements
%%  - `next_gc_ms' next interval time REDI will scan to remove oldest elements
%%

-spec start_link(atom(), map()) -> {ok, Pid :: pid()} |
		      {error, Error :: {already_started, pid()}} |
		      {error, Error :: term()} |
		      ignore.
start_link(Name, Opts) ->
    gen_server:start_link({local, Name}, ?MODULE, [Opts], []).

child_spec(Opts) ->
    #{
      id => ?MODULE,
      start => {?MODULE, start_link, Opts},
      shutdown => 500
     }.

%% helper when using multiple instances of redi
child_spec(BucketName, TTL_ms) when is_atom(BucketName) ->
    #{
      id => BucketName,
      start => {?MODULE, start_link, [BucketName,  #{bucket_name => BucketName, entry_ttl_ms => TTL_ms}]}
     }.

-spec delete(Gen_server :: pid(), Key :: term()) -> ok.
delete(Pid, Key) ->
    gen_server:call(Pid, {delete, Key}).

-spec gc_client(Gen_server :: pid(), Client :: pid()) -> ok.
gc_client(Redi_pid, Client_pid) when is_pid(Client_pid) ->
    gc_client(Redi_pid, Client_pid, #{returns => key}).

-spec gc_client(Gen_server :: pid(), Client :: pid(), Opts :: maps:maps()) -> ok.
gc_client(Redi_pid, Client_pid, Opts) when is_pid(Client_pid), is_map(Opts) ->
    gen_server:call(Redi_pid, {gc_client, Client_pid, maps:get(returns, Opts)}).

%% @doc
%% returns ets:lookup(Bucket_name, Key)
%% returns [] if no entry is found
%% returns [{key,data}, ..] if there is at least an entry
%%
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
    case ets:info(Bucket_name, size) of
	undefined ->
	    {error, undefined_bucket};
	_ ->
	    gen_server:call(Pid, {set, Key, Value, Bucket_name})
    end.

-spec set_bulk(Gen_server :: pid(), Key :: term(), Value :: term()) -> ok.
set_bulk(Pid, Key, Value) ->
    gen_server:call(Pid, {set_bulk, Key, Value}).

-spec set_bulk(Gen_server :: pid(), Key :: term(), Value :: term(), Bucket_name ::atom()) -> ok.
set_bulk(Pid, Key, Value, Bucket_name) when is_atom(Bucket_name) ->
    case ets:info(Bucket_name, size) of
	undefined ->
	    {error, undefined_bucket};
	_ ->
	    gen_server:call(Pid, {set_bulk, Key, Value, Bucket_name})
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

-spec all(Bucket_name :: atom()) -> list().
all(Bucket_name) ->
     ets:tab2list(Bucket_name).

%% @doc get value from Key / Bucket_name
%% if key is missing, call Fallback(Key) to update the cache
%% Returns the value
-spec get_maybe_update(Bucket_name :: atom(), Key :: term(), Fallback :: fun() ) -> term().
get_maybe_update(Key, Bucket, Fallback) when is_atom(Bucket), is_function(Fallback, 1) ->
    case redi:get(Bucket, Key) of
	[] ->
	    Val = Fallback(Key),
	    redi:set(Bucket, Key, Val),
	    Val;
	[{_,Val}] ->
	    Val
    end.

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
    rand:seed(exrop),
    {ok, #state{
	    next_gc_ms = Next_gc_ms,
	    bucket_name = Bucket_name,
	    entry_ttl_ms = maps:get(entry_ttl_ms, Opts, ?ENTRY_TTL_MS),
	    gc_q = queue:new()}}.


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

handle_call({set, Key, Value}, From, State) ->
    handle_call({set, Key, Value, State#state.bucket_name}, From, State);

handle_call({set, Key, Value, Bucket_name}, _From, #state{gc_q=GC_q}=State) ->
    NewGC_q = do_insert_gc(?ts_ms(), Key, GC_q),
    ets:insert(Bucket_name, {Key, Value}),
    {reply, ok, State#state{gc_q=NewGC_q}};

handle_call({set_bulk, Key, Value}, From, State) ->
    handle_call({set_bulk, Key, Value, State#state.bucket_name}, From, State);

handle_call({set_bulk, Key, Value, Bucket_name}, _From, #state{gc_q=GC_q, entry_ttl_ms=TTL}=State) ->
    NewGC_q = do_insert_gc(?ts_ms() + rand:uniform(TTL), Key, GC_q),
    ets:insert(Bucket_name, {Key, Value}),
    {reply, ok, State#state{gc_q=NewGC_q}};

handle_call(dump, _From, #state{gc_q=GC_q, bucket_name=Bucket_name}=State) ->
    {reply, {ets:tab2list(Bucket_name), queue:len(GC_q)}, State};

handle_call(get_bucket_name, _From, #state{bucket_name=Bucket_name}=State) ->
    {reply, Bucket_name, State};

handle_call({add_bucket, Bucket_name, Bucket_type}, _From, State) ->
    create_bucket(Bucket_name, Bucket_type),
    {reply, Bucket_name, State};

handle_call({gc_client, Pid, TypeReturns}, _From, State) ->
    {reply, ok,  State#state{gc_client={Pid, TypeReturns}}};

handle_call({delete, Key}, _From, #state{gc_q=GC_q, bucket_name=Bucket_name}=State) ->
    ets:delete(Bucket_name, Key),
    NewGC_q = queue:from_list(lists:keydelete(Key, 2, queue:to_list(GC_q))),
    {reply, ok,  State#state{gc_q=NewGC_q}}.


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
    erlang:send_after(State#state.next_gc_ms, self(), refresh_gc),
    T_gc_ms = ?ts_ms() - TTL,
    State2 = clean_older0(T_gc_ms, [], State),
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


do_insert_gc(Ts, Key, GC_q) when Ts  <  ?ts_non_gc ->
    queue:in({Ts,Key}, GC_q);
do_insert_gc(_Ts, _Key, GC_q) -> GC_q.

clean_older0(T_gc_ms, Acc, #state{gc_client= undefined}= State) ->

    case queue:peek(State#state.gc_q) of
	empty ->
	    State;
	{value, _V ={Ts, Key}} when Ts < T_gc_ms ->
	    ets:delete(State#state.bucket_name, Key),
	    GC1_q = queue:drop(State#state.gc_q),
	    clean_older0(T_gc_ms, Acc, State#state{gc_q = GC1_q});
	{value, _V}  ->
	     State
    end;

clean_older0(T_gc_ms, Acc, #state{gc_client= {_, TypeReturns}} = State) ->
    case queue:peek(State#state.gc_q) of
	empty ->
	    terminate_clean_older(Acc, State);
	{value, _V ={Ts, Key}} when Ts < T_gc_ms ->

	    Gc_ed_keys = case ets:lookup(State#state.bucket_name, Key) of
			     [] ->
				 Acc;
			     [Key_value] ->
				 ets:delete(State#state.bucket_name, Key),
				 if
				     TypeReturns == key_value ->
					 [Key_value|Acc];
				     true ->
					 [Key|Acc]
				 end;
			     Key_values ->
				 ets:delete(State#state.bucket_name, Key),
				 if
				     TypeReturns == key_value ->
					 lists:append(Key_values,Acc);
				     true ->
					 [Key|Acc]
				 end
			 end,
	    GC1_q = queue:drop(State#state.gc_q),
	    clean_older0(T_gc_ms, Gc_ed_keys, State#state{gc_q = GC1_q});
	{value, _V}  ->
	    terminate_clean_older(Acc, State)
    end.

terminate_clean_older(_Gc_ed_keys, #state{gc_client={undefined,_}}=State) ->
    State;
terminate_clean_older([], State) ->
    State;
terminate_clean_older(Gc_ed_keys, #state{gc_client={Pid,_}, bucket_name=Bucket}=State) ->
    erlang:send(Pid, {redi_gc, Bucket, Gc_ed_keys}),
    State.

create_bucket(Bucket_name, Bucket_type) ->
    ets:new(Bucket_name, [Bucket_type, named_table]).
