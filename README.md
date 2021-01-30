

# Erlang REDI: an ETS (local) cache without REDIS#

Copyright (c) 2019 Renaud Mariana.

__Version:__ 0.9.0.

## Erlang REDI

An erlang ETS (local) cache with TTL and without Redis.

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

Redi is a gen_server that could be added to a supervision tree.

Example:
------

Its usage is very simple.

$ rebar3 shell

```erlang

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
$ rebar3 eunit

Registering to keys that are GCed
------

```erlang
redi:gc_client(Redi_Pid, self(), Opts).

receive
	{redi_gc, _, Keys} -> ok

%% see more examples in unit tests
```


elixir:
------

mix.exs

```elixir
      {:redi, git: "git://github.com/bougueil/erlang-redi", app: false},
```

application.ex 
start redi inside a supervisor :

 ```elixir
  children = [
     {:redi,
         [:redi_dns,  # process name
          %{bucket_name: :dns, entry_ttl_ms: :timer.minutes(5)} ]}
  ]
```      
