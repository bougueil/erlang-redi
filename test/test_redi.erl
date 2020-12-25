-module(test_redi).
-include_lib("eunit/include/eunit.hrl").

redi_set_test() ->
    Bucket_name = test_set,
    Next_gc_ms = 20,
    TTL = 10 * Next_gc_ms,
    {ok, Pid} = redi:start_link(#{bucket_name => Bucket_name,
				  next_gc_ms => Next_gc_ms,
				  entry_ttl_ms=> TTL}),
    redi:gc_client(Pid, self()),
    redi:set(Pid, <<"set_a">>, some_data),
    redi:set(Pid, <<"set_a">>, some_data2),
    redi:set(Pid, <<"set_b">>, some_data),

    redi:set(Pid, <<"set_c">>, some_data),
    redi:set(Pid, <<"set_c">>, some_data2),
    redi:set(Pid, <<"set_d">>, some_data),
    [{<<"set_a">>, some_data2}] = redi:get(Bucket_name, <<"set_a">>),
    redi:delete(Pid, <<"set_a">>),

    ?assertEqual(redi:get(Bucket_name, <<"set_a">>), []),
    ?assertEqual(redi:size(Bucket_name), 3),

    %% 5 keys queued for gc
    %% <<"set_d">>,<<"set_c">>,<<"set_c">>,<<"set_b">>,<<"set_a">>
    wait_N_gc(5, Bucket_name),

    ?assertEqual(redi:size(Bucket_name), 0),
    ?assertEqual(redi:get(Bucket_name, <<"set_a">>), []),

    %% multi buckets
    redi:add_bucket(Pid, another_bucket, bag),
    redi:set(Pid, <<"set_a">>, some_data, another_bucket),
    ?assertEqual(redi:get(another_bucket, <<"set_a">>), [{<<"set_a">>, some_data}]),

    redi:stop(Pid).

redi_bag_test() ->
    Bucket_name = test_bag,
    Next_gc_ms = 20,
    TTL = 10 * Next_gc_ms,
    {ok, Pid} = redi:start_link(#{bucket_name => Bucket_name,
				  bucket_type => bag,
				  next_gc_ms => Next_gc_ms,
				  entry_ttl_ms=> TTL}),
    redi:gc_client(Pid, self()),
    redi:set(Pid, <<"bag_a">>, some_data),
    redi:set(Pid, <<"bag_a">>, some_data2),
    redi:set(Pid, <<"bag_b">>, some_data),

    redi:set(Pid, <<"bag_c">>, some_data),
    redi:set(Pid, <<"bag_c">>, some_data2),
    redi:set(Pid, <<"bag_d">>, some_data),

    [{<<"bag_a">>,some_data},{<<"bag_a">>,some_data2}] = redi:get(Bucket_name, <<"bag_a">>),
    redi:delete(Pid, <<"bag_a">>),

    ?assertEqual(redi:get(Bucket_name, <<"bag_a">>), []),
    ?assertEqual(redi:size(Bucket_name), 4),

    %% 5 keys queued for gc
    wait_N_gc(5, Bucket_name),

    ?assertEqual(redi:size(Bucket_name), 0),
    ?assertEqual(redi:get(Bucket_name, <<"bag_a">>), []),

    %% %% multi buckets
    redi:add_bucket(Pid, another_bucket, bag),
    redi:set(Pid, <<"bag_a">>, data1, another_bucket),
    redi:set(Pid, <<"bag_a">>, data2, another_bucket),
    ?assertEqual(redi:get(another_bucket, <<"bag_a">>), [{<<"bag_a">>, data1}, {<<"bag_a">>, data2}]),

    redi:stop(Pid).


redi_set_bulk_test() ->
    Bucket_name = test_bulk,
    Next_gc_ms = 20,
    TTL = 5 * Next_gc_ms,
    {ok, Pid} = redi:start_link(#{bucket_name => Bucket_name,
				  next_gc_ms => Next_gc_ms,
				  entry_ttl_ms=> TTL}),
    redi:gc_client(Pid, self()),
    redi:set_bulk(Pid, <<"bulk_a">>, some_data),
    redi:set_bulk(Pid, <<"bulk_a">>, some_data2),
    redi:set_bulk(Pid, <<"bulk_b">>, some_data),

    redi:set_bulk(Pid, <<"bulk_c">>, some_data),
    redi:set_bulk(Pid, <<"bulk_c">>, some_data2),
    redi:set_bulk(Pid, <<"bulk_d">>, some_data),
    [{<<"bulk_a">>, some_data2}] = redi:get(Bucket_name, <<"bulk_a">>),
    redi:delete(Pid, <<"bulk_a">>),

    ?assertEqual(redi:get(Bucket_name, <<"bulk_a">>), []),
    ?assertEqual(redi:size(Bucket_name), 3),

    %% 5 keys queued for gc
    wait_N_gc(5, Bucket_name),

    ?assertEqual(redi:size(Bucket_name), 0),
    ?assertEqual(redi:get(Bucket_name, <<"bulk_a">>), []),

    %% multi buckets
    redi:add_bucket(Pid, another_bucket, bag),
    redi:set_bulk(Pid, <<"bulk_a">>, some_data, another_bucket),
    ?assertEqual(redi:get(another_bucket, <<"bulk_a">>), [{<<"bulk_a">>, some_data}]),

    redi:stop(Pid).


heavy_test() ->
    Pid_name = heavy_redi,
    Bucket_name = heavy_test,
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
    Next_gc_ms = 10,
    TTL = 10 * Next_gc_ms,
    {ok, Pid} = redi:start_link(#{bucket_name => Bucket_name,
				  next_gc_ms => 10,
				  entry_ttl_ms=> TTL}),

    redi:set(Pid, <<"aaa">>, some_data),
    timer:sleep(8 * Next_gc_ms),
    redi:set(Pid, <<"aaa">>, some_data1),
    timer:sleep(3 * Next_gc_ms),
    redi:set(Pid, <<"aaa">>, some_data2),
    ?assertEqual(redi:dump(Pid), {[{<<"aaa">>,some_data2}],2}),
    timer:sleep(8 * Next_gc_ms),
    ?assertEqual(redi:dump(Pid), {[],1}),
    redi:stop(Pid).

wait_N_gc(0, Test_name) ->
    ?debugFmt("~s all keys gc'ed", [Test_name]),
    ok;
wait_N_gc(Num_keys, Test_name) ->
    receive
	{redi_gc, _, Keys} ->
	    ?debugFmt("~p rcv gc for keys ~p, remains: ~p keys", [Test_name, Keys, Num_keys - length(Keys) ]),
 	    wait_N_gc(Num_keys - length(Keys), Test_name)
    end.
