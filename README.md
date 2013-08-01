# Ecto

Ecto is a domain specific language for writing database queries in Elixir.

### Contributing

Ecto is on the bleeding edge of Elixir so the latest master build is most likely needed, see [Elixir's README](https://github.com/elixir-lang/elixir) on how to build from source.

To contribute you need to compile Ecto from source and test it:

```
$ git clone https://github.com/elixir-lang/ecto.git
$ cd ecto
$ mix test
```

If you are contributing to the Postgres adapter you need to run the integration tests for the adapter (it is a good idea to run the integration tests even if you are not contributing to the the adapter). You need a Postgres user with username `postgres` and password `postgres` or with trust authentication. To run the tests the `MIX_ENV` environment variable needs to be set to `pg` when running the tests. To run only the integration tests: `MIX_ENV=pg mix test` or to run all tests: `mix test && MIX_ENV=pg mix test`.

### Usage

Add Ecto as a dependency in your `mix.exs` file. If you are using PostgreSQL, you will also need the library that Ecto's adapter is using.

```elixir
def deps do
  [ { :ecto, github: "elixir-lang/ecto" },
    { :pgsql, github: "semiocast/pgsql" } ]
end
```

After you are done, run `mix deps.get` in your shell to fetch and compile the dependencies.

There are three key components that makes up Ecto: repositories, entities and, of course, queries. Repositories map to a database, you define an adapter to use and an Ecto URL so it knows how to connect to the database and the repository will handle the connections to the database. Entities are Elixir records that, with the specified metadata, map to a database table. Queries select data from an entity and are executed against a repository.

Define a repository:

```elixir
defmodule MyRepo do
  use Ecto.Repo, adapter: Ecto.Adapter.Postgres

  def url, do: "ecto://eric:hunter42@localhost/mydb"
end
```

Create an entity:

```elixir
defmodule Post do
  use Ecto.Entity

  dataset :posts do
    field :title, :string
    field :content, :string
  end
end
```

Run a query:

```elixir
import Ecto.Query

# A query that will fetch the ten first post titles
query = from p in Post,
      where: p.id <= 10,
     select: p.title

# Run the query against the database to actually fetch the data
titles = MyRepo.fetch(query)
```

### Examples

There are example applications in the `examples/` directory.
