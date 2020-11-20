-module(test_redi).
-include_lib("eunit/include/eunit.hrl").

redi_test() ->
    Bucket_name = test,
    Next_gc_ms = 20,
    TTL = 10 * Next_gc_ms,
    {ok, Pid} = redi:start_link(#{bucket_name => Bucket_name,
				  next_gc_ms => Next_gc_ms,
				  entry_ttl_ms=> TTL}),
    redi:gc_client(Pid, self()),
    redi:set(Pid, <<"aaa">>, some_data),
    redi:set(Pid, <<"aaa">>, some_data2),
    redi:set(Pid, <<"bbb">>, some_data),

    redi:set(Pid, <<"ccc">>, some_data),
    redi:set(Pid, <<"ccc">>, some_data2),
    redi:set(Pid, <<"ddd">>, some_data),
    [{<<"aaa">>, some_data2}] = redi:get(Bucket_name, <<"aaa">>),
    redi:delete(Pid, <<"aaa">>), 

    ?assertEqual(redi:get(Bucket_name, <<"aaa">>), []),
    ?assertEqual(redi:size(Bucket_name), 3),

     %% wait data expiration 5 keys
    wait_N_gc(5, "redi_test"),

    ?assertEqual(redi:size(Bucket_name), 0),
    ?assertEqual(redi:get(Bucket_name, <<"aaa">>), []),

    %% multi buckets
    redi:add_bucket(Pid, another_bucket, bag),
    redi:set(Pid, <<"aaa">>, some_data, another_bucket),
    ?assertEqual(redi:get(another_bucket, <<"aaa">>), [{<<"aaa">>, some_data}]),

    redi:stop(Pid).

redi_bulk_test() ->
    Bucket_name = test,
    Next_gc_ms = 20,
    TTL = 5 * Next_gc_ms,
    {ok, Pid} = redi:start_link(#{bucket_name => Bucket_name,
				  next_gc_ms => Next_gc_ms,
				  entry_ttl_ms=> TTL}),
    redi:gc_client(Pid, self()),
    redi:set_bulk(Pid, <<"aaa">>, some_data),
    redi:set_bulk(Pid, <<"aaa">>, some_data2),
    redi:set_bulk(Pid, <<"bbb">>, some_data),

    redi:set_bulk(Pid, <<"ccc">>, some_data),
    redi:set_bulk(Pid, <<"ccc">>, some_data2),
    redi:set_bulk(Pid, <<"ddd">>, some_data),
    [{<<"aaa">>, some_data2}] = redi:get(Bucket_name, <<"aaa">>),
    redi:delete(Pid, <<"aaa">>), 

    ?assertEqual(redi:get(Bucket_name, <<"aaa">>), []),
    ?assertEqual(redi:size(Bucket_name), 3),

    %% wait data expiration 5 keys
     wait_N_gc(5, "redi_bulk_test"),

    ?assertEqual(redi:size(Bucket_name), 0),
    ?assertEqual(redi:get(Bucket_name, <<"aaa">>), []),

    %% multi buckets
    redi:add_bucket(Pid, another_bucket, bag),
    redi:set_bulk(Pid, <<"aaa">>, some_data, another_bucket),
    ?assertEqual(redi:get(another_bucket, <<"aaa">>), [{<<"aaa">>, some_data}]),

    redi:stop(Pid).


heavy_test() ->
    Pid_name = heavy_redi,
    Bucket_name = test,
    {ok, _Pid} = redi:start_link(Pid_name,
				#{bucket_name => Bucket_name,
				  next_gc_ms => 10000,
				  entry_ttl_ms=> 30000}),
    N = 20000,
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

redi_2_set_test() ->
    Bucket_name = test,
    TTL = 1000,
    {ok, Pid} = redi:start_link(#{bucket_name => Bucket_name,
				  next_gc_ms => 100,
				  entry_ttl_ms=> TTL}),

    redi:set(Pid, <<"aaa">>, some_data),
    timer:sleep(800),
    redi:set(Pid, <<"aaa">>, some_data1),
    timer:sleep(300),
    redi:set(Pid, <<"aaa">>, some_data2),
    ?assertEqual(redi:dump(Pid), {[{<<"aaa">>,some_data2}],2}),
    timer:sleep(800),
    ?assertEqual(redi:dump(Pid), {[],1}),
    redi:stop(Pid).

wait_N_gc(0, _Test_name) ->
    ok;
wait_N_gc(Num_keys, Test_name) ->
    receive
	{redi_gc, _, Keys} ->
	    ?debugFmt("~s rcv gc for keys ~p, remains: ~p keys", [Test_name, Keys, Num_keys - length(Keys) ]),
 	    wait_N_gc(Num_keys - length(Keys), Test_name)
    end.
