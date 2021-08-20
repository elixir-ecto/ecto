<img width="250" src="https://github.com/elixir-ecto/ecto/raw/master/guides/images/logo.png" alt="Ecto">

---

[![Build Status](https://github.com/elixir-ecto/ecto/workflows/CI/badge.svg)](https://github.com/elixir-ecto/ecto/actions) [![Hex.pm](https://img.shields.io/hexpm/v/ecto.svg)](https://hex.pm/packages/ecto)

Ecto is a toolkit for data mapping and language integrated query for Elixir. Here is an example:

```elixir
# In your config/config.exs file
config :my_app, ecto_repos: [Sample.Repo]

config :my_app, Sample.Repo,
  database: "ecto_simple",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: "5432"

# In your application code
defmodule Sample.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres
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
  alias Sample.{Weather, Repo}

  def keyword_query do
    query =
      from w in Weather,
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

Ecto is commonly used to interact with databases, such as Postgres and MySQL via [Ecto.Adapters.SQL](http://hexdocs.pm/ecto_sql) ([source code](https://github.com/elixir-ecto/ecto_sql)). Ecto is also commonly used to map data from any source into Elixir structs, whether they are backed by a database or not.

See the [getting started guide](http://hexdocs.pm/ecto/getting-started.html) and the [online documentation](http://hexdocs.pm/ecto) for more information. Other resources available are:

  * [Programming Ecto](https://pragprog.com/book/wmecto/programming-ecto), by Darin Wilson and Eric Meadows-Jönsson, which guides you from fundamentals up to advanced concepts

  * [The Little Ecto Cookbook](https://dashbit.co/ebooks/the-little-ecto-cookbook), a free ebook by Dashbit, which is a curation of the existing Ecto guides with some extra contents

## Usage

You need to add both Ecto and the database adapter as a dependency to your `mix.exs` file. The supported databases and their adapters are:

Database   | Ecto Adapter           | Dependencies
:----------| :--------------------- | :-----------------------------------------------
PostgreSQL | Ecto.Adapters.Postgres | [ecto_sql][ecto_sql] (requires Ecto v3.0+) + [postgrex][postgrex]
MySQL      | Ecto.Adapters.MyXQL    | [ecto_sql][ecto_sql] (requires Ecto v3.3+) + [myxql][myxql]
MSSQL      | Ecto.Adapters.Tds      | [ecto_sql][ecto_sql] (requires Ecto v3.4+) + [tds][tds]
SQLite3    | Ecto.Adapters.SQLite3  | [ecto_sql][ecto_sql] (requires Ecto v3.5+) + [ecto_sqlite3][ecto_sqlite3]
ETS        | Etso                   | [ecto][ecto] + [etso][etso]

[ecto]: http://github.com/elixir-ecto/ecto
[ecto_sql]: http://github.com/elixir-ecto/ecto_sql
[postgrex]: http://github.com/elixir-ecto/postgrex
[myxql]: http://github.com/elixir-ecto/myxql
[tds]: https://github.com/livehelpnow/tds
[ecto_sqlite3]: https://github.com/elixir-sqlite/ecto_sqlite3
[etso]: https://github.com/evadne/etso

For example, if you want to use PostgreSQL, add to your `mix.exs` file:

```elixir
defp deps do
  [
    {:ecto_sql, "~> 3.0"},
    {:postgrex, ">= 0.0.0"}
  ]
end
```

Then run `mix deps.get` in your shell to fetch the dependencies. If you want to use another database, just choose the proper dependency from the table above.

Finally, in the repository definition, you will need to specify the `adapter:` respective to the chosen dependency. For PostgreSQL it is:

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres,
  ...
```

## Supported Versions

| Branch | Support                  |
| ------ | ------------------------ |
| v3.3   | Bug fixes                |
| v3.2   | Security patches only    |
| v3.1   | Unsupported from 02/2020 |
| v3.0   | Unsupported from 02/2020 |
| v2.2   | Security patches only    |
| v2.1   | Unsupported from 10/2018 |
| v2.0   | Unsupported from 08/2017 |
| v1.1   | Unsupported from 03/2018 |
| v1.0   | Unsupported from 05/2017 |

With the version 3.0, Ecto has become API stable. This means our main focus is on providing bug fixes and updates.

## Important links

  * [Documentation](http://hexdocs.pm/ecto)
  * [Mailing list](https://groups.google.com/forum/#!forum/elixir-ecto)
  * [Examples](https://github.com/elixir-ecto/ecto/tree/master/examples)

## Running tests

Clone the repo and fetch its dependencies:

    $ git clone https://github.com/elixir-ecto/ecto.git
    $ cd ecto
    $ mix deps.get
    $ mix test

Note that `mix test` does not run the tests in the `integration_test` folder. To run integration tests, you can clone `ecto_sql` in a sibling directory and then run its integration tests with the `ECTO_PATH` environment variable pointing to your Ecto checkout:

    $ cd ..
    $ git clone https://github.com/elixir-ecto/ecto_sql.git
    $ cd ecto_sql
    $ mix deps.get
    $ ECTO_PATH=../ecto mix test.all

### Running containerized tests

It is also possible to run the integration tests under a containerized environment using [earthly](https://earthly.dev/get-earthly):

    $ earthly -P +all

You can also use this to interactively debug any failing integration tests using:

    $ earthly -P -i --build-arg ELIXIR_BASE=1.8.2-erlang-21.3.8.21-alpine-3.13.1 +integration-test

Then once you enter the containerized shell, you can inspect the underlying databases with the respective commands:

    PGPASSWORD=postgres psql -h 127.0.0.1 -U postgres -d postgres ecto_test
    MYSQL_PASSWORD=root mysql -h 127.0.0.1 -uroot -proot ecto_test
    sqlcmd -U sa -P 'some!Password'

## Logo

"Ecto" and the Ecto logo are Copyright (c) 2020 Dashbit.

The Ecto logo was designed by [Dane Wesolko](http://www.danewesolko.com).

## License

Copyright (c) 2013 Plataformatec \
Copyright (c) 2020 Dashbit

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
