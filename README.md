

# Erlang REDI: a Redis subset with global TTL . #

Copyright (c) 2018 Renaud Mariana.

__Version:__ 1.0.0.

## Erlang REDI

Erlang REDI implements a small subset of Redis with a global TTL.

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
redi:get(Bucket, <<"aaa">>),

...
```

## Documentation


