# Ecto

[![Build Status](https://travis-ci.org/elixir-lang/ecto.svg?branch=master)](https://travis-ci.org/elixir-lang/ecto)
[![Inline docs](http://inch-ci.org/github/elixir-lang/ecto.svg?branch=master&style=flat)](http://inch-ci.org/github/elixir-lang/ecto)

Ecto is a domain specific language for writing queries and interacting with databases in Elixir. Here is an example:

```elixir
# In your config/config.exs file
config :my_app, Sample.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "ecto_simple",
  username: "postgres",
  password: "postgres"

# In your application code
defmodule Sample.Repo do
  use Ecto.Repo,
    otp_app: :my_app
end

defmodule Sample.Weather do
  use Ecto.Model

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

  def sample_query do
    query = from w in Weather,
          where: w.prcp > 0 or is_nil(w.prcp),
         select: w
    Repo.all(query)
  end
end
```

See the [online documentation](http://hexdocs.pm/ecto) or [run the sample application](https://github.com/elixir-lang/ecto/tree/master/examples/simple) for more information.

## Usage

You need to add both Ecto and the database adapter as a dependency to your `mix.exs` file. The supported databases and their adapters are:

Database                | Ecto Adapter           | Dependency
:---------------------- | :--------------------- | :-------------------
PostgreSQL              | Ecto.Adapters.Postgres | [postgrex][postgrex]
MySQL                   | Ecto.Adapters.MySQL    | [mariaex][mariaex]
MSSQL                   | Tds.Ecto               | [tds_ecto][tds_ecto]
SQLite3                 | Sqlite.Ecto            | [sqlite_ecto][sqlite_ecto]
MongoDB                 | Mongo.Ecto             | [mongodb_ecto][mongodb_ecto]

[postgrex]: http://github.com/ericmj/postgrex
[mariaex]: http://github.com/xerions/mariaex
[tds_ecto]: https://github.com/livehelpnow/tds_ecto
[sqlite_ecto]: https://github.com/jazzyb/sqlite_ecto
[mongodb_ecto]: https://github.com/michalmuskala/mongodb_ecto

For example, if you want to use PostgreSQL, add to your `mix.exs` file:

```elixir
defp deps do
  [{:postgrex, ">= 0.0.0"},
   {:ecto, "~> 1.0"}]
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
  * [Examples](https://github.com/elixir-lang/ecto/tree/master/examples)

## Contributing

Ecto is on the bleeding edge of Elixir so the latest master build is most likely needed, see [Elixir's README](https://github.com/elixir-lang/elixir) on how to build from source.

To contribute you need to compile Ecto from source and test it:

```
$ git clone https://github.com/elixir-lang/ecto.git
$ cd ecto
$ mix deps.get
$ mix test
```

Besides the unit tests above, it is recommended to run the adapter integration tests too:

```
# Run only PostgreSQL tests (version of PostgreSQL must be >= 9.4 to support jsonb)
MIX_ENV=pg mix test

# Run all tests (unit and all adapters/pools)
mix test.all
```

In addition, build the docs locally to review any changes:

```
$ MIX_ENV=docs mix docs
```

## License

Copyright 2012 Plataformatec

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
