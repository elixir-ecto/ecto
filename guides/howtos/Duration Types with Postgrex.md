# Duration Types with Postgrex

As of Ecto 3.12.0, Ecto supports a `:duration` type which maps to Elixir's `Duration` struct (available as of Elixir 1.17).

One natural use case for this is when using Postgres's `interval` type. Historically, Postgrex loads intervals from the database into a custom `Postgrex.Interval` struct. With the introduction of `Duration`, there is now the option to choose between the two. Please follow the steps below to enable mapping to `Duration`.

1. Define your migration

```elixir
create table("movies") do
  add :running_time, :interval
end
```

2. Define your schema

```elixir
defmodule Movie do
  use Ecto.Schema

  schema "movies" do
    field :running_time, :duration
  end
end
```

3. Define your custom Postgrex type module and specify intervals should decode to `Duration`

```elixir
# Inside lib/my_app/postgrex_types.ex

Postgrex.Types.define(MyApp.PostgrexTypes, [], interval_decode_type: Duration)
```

4.  Make Ecto aware of the Postgrex type module in your configuration

```elixir
config :my_app, MyApp.Repo, types: MyApp.PostgresTypes
```
