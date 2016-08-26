# Ecto

[![Build Status](https://travis-ci.org/elixir-ecto/ecto.svg?branch=master)](https://travis-ci.org/elixir-ecto/ecto)
[![Inline docs](http://inch-ci.org/github/elixir-ecto/ecto.svg?branch=master&style=flat)](http://inch-ci.org/github/elixir-ecto/ecto)

Ecto is a domain specific language for writing queries and interacting with databases in Elixir. Here is an example:

```elixir
# In your config/config.exs file
config :my_app, ecto_repos: [Sample.Repo]

config :my_app, Sample.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "ecto_simple",
  username: "postgres",
  password: "postgres",
  host: "localhost",
  port: "5432"

# In your application code
defmodule Sample.Repo do
  use Ecto.Repo,
    otp_app: :my_app
end

defmodule Sample.Weather do
  use Ecto.Schema

  schema "weather" do
    field :city     # Defaults to type :string
    field :temp_lo, :integer
    field :temp_hi, :integer
    field :prcp,    :float, default: 0.0
  end
end

defmodule Sample.App do
  import Ecto.Query
  alias Sample.Weather
  alias Sample.Repo

  def keyword_query do
    query = from w in Weather,
         where: w.prcp > 0 or is_nil(w.prcp),
         select: w
    Repo.all(query)
  end

  def pipe_query do
    Weather
    |> where(city: "Kraków")
    |> order_by(:temp_lo)
    |> limit(10)
    |> Repo.all
  end
end
```

See the [getting started guide](http://hexdocs.pm/ecto/getting-started.html) and the [online documentation](http://hexdocs.pm/ecto).

## Usage

You need to add both Ecto and the database adapter as a dependency to your `mix.exs` file. The supported databases and their adapters are:

Database   | Ecto Adapter           | Dependency                   | Ecto 2.0 compatible?
:----------| :--------------------- | :----------------------------| :-------------------
PostgreSQL | Ecto.Adapters.Postgres | [postgrex][postgrex]         | Yes
MySQL      | Ecto.Adapters.MySQL    | [mariaex][mariaex]           | Yes
MSSQL      | Tds.Ecto               | [tds_ecto][tds_ecto]         | No
SQLite3    | Sqlite.Ecto            | [sqlite_ecto][sqlite_ecto]   | No
MongoDB    | Mongo.Ecto             | [mongodb_ecto][mongodb_ecto] | No

[postgrex]: http://github.com/ericmj/postgrex
[mariaex]: http://github.com/xerions/mariaex
[tds_ecto]: https://github.com/livehelpnow/tds_ecto
[sqlite_ecto]: https://github.com/jazzyb/sqlite_ecto
[mongodb_ecto]: https://github.com/michalmuskala/mongodb_ecto

For example, if you want to use PostgreSQL, add to your `mix.exs` file:

```elixir
defp deps do
  [{:postgrex, ">= 0.0.0"},
   {:ecto, "~> 2.0.0"}]
end
```

and update your applications list to include both projects:

```elixir
def application do
  [applications: [:postgrex, :ecto]]
end
```

Then run `mix deps.get` in your shell to fetch the dependencies. If you want to use another database, just choose the proper dependency from the table above.

Finally, in the repository configuration, you will need to specify the `adapter:` respective to the chosen dependency. For PostgreSQL it is:

```elixir
config :my_app, Repo,
  adapter: Ecto.Adapters.Postgres,
  ...
```

We are currently looking for contributions to add support for other SQL databases and folks interested in exploring non-relational databases too.

## Important links

  * [Documentation](http://hexdocs.pm/ecto)
  * [Mailing list](https://groups.google.com/forum/#!forum/elixir-ecto)
  * [Examples](https://github.com/elixir-ecto/ecto/tree/master/examples)

## Contributing

Contributions are welcome! In particular, remember to:

* Do not use the issues tracker for help or support requests (try Stack Overflow, IRC or mailing lists, etc).
* For proposing a new feature, please start a discussion on [elixir-ecto](https://groups.google.com/forum/#!forum/elixir-ecto).
* For bugs, do a quick search in the issues tracker and make sure the bug has not yet been reported.
* Finally, be nice and have fun! Remember all interactions in this project follow the same [Code of Conduct as Elixir](https://github.com/elixir-lang/elixir/blob/master/CODE_OF_CONDUCT.md).

### Running tests

Clone the repo and fetch its dependencies:

```
$ git clone https://github.com/elixir-ecto/ecto.git
$ cd ecto
$ mix deps.get
$ mix test
```

Besides the unit tests above, it is recommended to run the adapter integration tests too:

```
# Run only PostgreSQL tests (version of PostgreSQL must be >= 9.4 to support jsonb)
MIX_ENV=pg mix test

# Run all tests (unit and all adapters)
mix test.all
```

### Building docs

```
$ MIX_ENV=docs mix docs
```

## Copyright and License

Copyright (c) 2012, Plataformatec.

Ecto source code is licensed under the [Apache 2 License](LICENSE.md).
