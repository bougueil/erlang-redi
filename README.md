

# Erlang REDI: a local cache with a fixed TTL "a la Redis" . #

Copyright (c) 2018 Renaud Mariana.

__Version:__ 1.0.0.

## Erlang REDI

Erlang REDI implements a local cache with a fixed TTL.
An entriy TTL is not refreshed when the entry re-enters the cache.

The cache is a gen_server that could be added to a supervision tree.

Usage:
------

Its usage is very simple.

$ rebar3 shell

```erlang

Bucket = test,
{ok, Pid} = redi:start_link(#{bucket_name => Bucket,
		       entry_ttl_ms=> 30000}),

redi:set(Pid, <<"aaa">>, <<"data.aaa1">>), 
redi:set(Pid, <<"aaa">>, <<"data.aaa2">>), 
redi:set(Pid, <<"bbb">>, <<"data.xxl">>),
redi:delete(Pid, <<"bbb">>),
redi:get(Bucket, <<"aaa">>).

%% working with several buckets
redi:add_bucket(Pid, another_bucket, bag),
redi:set(Pid, <<"aaa">>, <<"data.aaay">>, another_bucket),
redi:get(another_bucket, <<"aaa">>).
...
```

## Documentation


