# Erlang REDI: an ETS cache without REDIS

Copyright (c) 2019-24 Renaud Mariana.

[![hex.pm badge](https://img.shields.io/badge/Package%20on%20hex.pm-informational)](https://hex.pm/packages/redi)
[![Erlang CI](https://github.com/bougueil/erlang-redi/actions/workflows/ci.yml/badge.svg)](https://github.com/bougueil/erlang-redi/actions/workflows/ci.yml)


## Erlang Redi

An erlang ETS cache with TTL.

The typical usage is:
```
case redi:get(..) of
     [] ->
       get the value from slow storage
       redi:set(..)
     [value] ->
       use value ...
end
```

This service ensures that data hold by the cache are `fresh enough` (<= TTL) and ***doesn't guarantee*** that data before their TTL expiration are still in sync with the underlying storage, but this is good enough for our use cases.

Redi is a gen_server that could be added to a supervision tree.

### Example:


Its usage is very simple :

```erlang
$ rebar3 shell

Bucket = test,
{ok, Pid} = redi:start_link(#{bucket_name => Bucket,
		       entry_ttl_ms=> 30000}),

redi:set(Pid, <<"key1">>, <<"data11">>),
redi:set(Pid, <<"key1">>, <<"data12">>),
redi:set(Pid, <<"key2">>, <<"moredata">>),
redi:delete(Pid, <<"key2">>),
redi:get(Bucket, <<"key1">>).

%% working with several buckets
redi:add_bucket(Pid, another_bucket, bag),
redi:set(Pid, <<"keyx">>, <<"data.aaay">>, another_bucket),
redi:get(another_bucket, <<"keyx">>).
...
```

### Performance

Excerpt from a run of the unit test (i5-1235U)

- throughput 363464 writes/s.
- throughput **3478260** reads/s.

### Registering to keys that are GCed

```erlang
redi:gc_client(Redi_Pid, self(), Opts).

receive
	{redi_gc, _, Keys} -> ok

%% see more examples in unit tests
```

## Elixir

Redi requires Elixir v1.15 or later. Then add Redi as a dependency:

```elixir
def deps do
  [
    {:redi, "~> 0.8"},
  ]
end
```

### Starting Redi inside a supervisor :

```elixir
# application.ex 

children = [
     {:redi,
         [:redi_dns,  # 
          %{bucket_name: :dns, entry_ttl_ms: :timer.minutes(5)} ]}
]
```      
then Redi can be used as:
```elixir
:redi.set(Process.whereis(:redi_dns), "mykey", "a_value")
:redi.get(:dns, "mykey")
```
