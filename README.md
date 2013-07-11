# Ecto

Ecto is a domain specific language for writing database queries in Elixir.

### Usage

Add Ecto as a dependency in your `mix.exs` file. If you are using Postgresql you will also need the library that Ecto's adapter is using.

```elixir
def deps do
  [ { :ecto, github: "elixir-lang/ecto" },
    { :pgsql, github: "semiocast/pgsql" } ]
end
```

After you are done run `mix deps.get` in your shell to fetch and compile the dependencies.

There are three key components that makes up Ecto, repositories, entities and, of course, queries. Repositories maps to a database, you define an adapter to use and an Ecto URL so it knows how to connect to the database, the repository will handle the connections to the database. Entities are Elixir records that with the specified metadata maps to a database table. Queries select data from an entity and are executed against a repository.

Define a repository:

```elixir
defmodule MyRepo do
  use Ecto.Repo, adapter: Ecto.Adapter.Postgresql

  def url, do: "ecto://eric:hunter42@localhost/mydb"
end
```

Create an entity:

```elixir
defmodule Post do
  use Ecto.Entity

  schema :posts do
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
