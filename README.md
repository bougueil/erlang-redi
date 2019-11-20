

# Erlang and Elixir REDI: a local cache "a la Redis" . #

Copyright (c) 2019 Renaud Mariana.

__Version:__ 1.0.0.

## Erlang and Elixir REDI

Erlang and Elixir REDI implements a local cache with TTL.

An entry TTL is not updated when the entry re-enters the cache.
The typical usage is
```
case redi:get(..) of
     ..something_udefined.. ->
       ..get the value from slow storage
       redi:set(..)
     ..the_value -> .. use the value ...
end
```

The cache is a gen_server that could be added to a supervision tree.

Example:
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
$ rebar3 eunit

elixir:
------

mix.exs

```erlang
      {:redi, git: "git://github.com/bougueil/erlang-redi", app: false},
```

application.ex 
start redi inside a supervisor :

 ```erlang
 children = [
     ...,
     %{
        id: :redi_id,
        start:
          {:redi, :start_link,
           [
             :mycache,  # the redi gen_server process name
             %{bucket_name: :my_bucket_name, entry_ttl_ms: :timer.seconds(4000)}
           ]}
      },
      ...
  ]
```      
