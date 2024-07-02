# Friends

A sample application built for Ecto guides as described in
https://hexdocs.pm/ecto/getting-started.html.

# Setup

Update the PostgreSQL database config in `config/config.exs` if the below
commands don't work.

```sh
mix deps.get
mix test
mix run priv/repo/seeds.exs
```

Start the app through IEx session:

```sh
iex -S mix
```

Run below query to verify your setup:

```elixir
iex(1)> Friends.Person |> Ecto.Query.first |> Friends.Repo.one

03:00:00.198 [debug] QUERY OK source="people" db=0.6ms decode=1.2ms queue=1.0ms idle=1384.7ms
SELECT p0."id", p0."first_name", p0."last_name", p0."age" FROM "people" AS p0 ORDER BY p0."id" LIMIT 1 []
%Friends.Person{
  __meta__: #Ecto.Schema.Metadata<:loaded, "people">,
  id: 1,
  first_name: "Ryan",
  last_name: "Bigg",
  age: 28
}
```
