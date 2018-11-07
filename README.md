<img width="250" src="https://github.com/elixir-ecto/ecto/raw/master/guides/images/logo.png" alt="Ecto">

---

[![Build Status](https://travis-ci.org/elixir-ecto/ecto.svg?branch=master)](https://travis-ci.org/elixir-ecto/ecto)

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

Ecto is commonly used to interact with databases, such as Postgres and MySQL via [Ecto.Adapters.SQL](http://hexdocs.pm/ecto_sql) ([source code](https://github.com/elixir-ecto/ecto_sql)). Ecto is also commonly used to map data from any source into Elixir structs, regardless if they are backed by a database or not.

See the [getting started guide](http://hexdocs.pm/ecto/getting-started.html) and the [online documentation](http://hexdocs.pm/ecto).

Also checkout the ["What's new in Ecto 2.1"](http://pages.plataformatec.com.br/ebook-whats-new-in-ecto-2-0) free ebook to learn more about many features since Ecto 2.1 such as `many_to_many`, schemaless queries, concurrent testing, upsert and more. Note the book still largely applies to Ecto 3.0 as the major change in Ecto 3.0 was the split of Ecto in two repositories (`ecto` and `ecto_sql`) and the removal of the outdated Ecto datetime types in favor of Elixir's Calendar types.

## Usage

You need to add both Ecto and the database adapter as a dependency to your `mix.exs` file. The supported databases and their adapters are:

Database   | Ecto Adapter           | Dependencies                                    | Ecto 3.0 compatible?
:----------| :--------------------- | :-----------------------------------------------| :----
PostgreSQL | Ecto.Adapters.Postgres | [ecto_sql][ecto_sql] + [postgrex][postgrex]     | Yes
MySQL      | Ecto.Adapters.MySQL    | [ecto_sql][ecto_sql] + [mariaex][mariaex]       | Yes
MSSQL      | MssqlEcto              | [ecto_sql][ecto_sql] + [mssql_ecto][mssql_ecto] | No
MSSQL      | Tds.Ecto               | [ecto_sql][ecto_sql] + [tds_ecto][tds_ecto]     | No
SQLite     | Sqlite.Ecto2           | [ecto][ecto] + [sqlite_ecto2][sqlite_ecto2]     | No
Mnesia     | EctoMnesia.Adapter     | [ecto][ecto] + [ecto_mnesia][ecto_mnesia]       | No

[ecto]: http://github.com/elixir-ecto/ecto
[ecto_sql]: http://github.com/elixir-ecto/ecto_sql
[postgrex]: http://github.com/elixir-ecto/postgrex
[mariaex]: http://github.com/xerions/mariaex
[mssql_ecto]: https://github.com/findmypast-oss/mssql_ecto
[tds_ecto]: https://github.com/livehelpnow/tds_ecto
[sqlite_ecto2]: https://github.com/scouten/sqlite_ecto2
[ecto_mnesia]: https://github.com/Nebo15/ecto_mnesia

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
| v3.0   | Bug fixes                |
| v2.2   | Security patches only    |
| v2.1   | Unsupported from 10/2018 |
| v2.0   | Unsupported from 08/2017 |
| v1.1   | Unsupported from 03/2018 |
| v1.0   | Unsupported from 05/2017 |

With the version 3.0, Ecto has become API stable. This means no more new features, although we will continue providing bug fixes and updates. For everyone running Ecto in production, rest assured that Ecto will continue to be a well maintained project with the same production quality and polish that our users are familiar with.

## Important links

  * [Documentation](http://hexdocs.pm/ecto)
  * [Mailing list](https://groups.google.com/forum/#!forum/elixir-ecto)
  * [Examples](https://github.com/elixir-ecto/ecto/tree/master/examples)

### Running tests

Clone the repo and fetch its dependencies:

    $ git clone https://github.com/elixir-ecto/ecto.git
    $ cd ecto
    $ mix deps.get
    $ mix test

## Copyright and License

"Ecto" and the Ecto logo are Copyright (c) 2012 Plataformatec.

The Ecto logo was designed by [Dane Wesolko](http://www.danewesolko.com).

The source code is under the Apache 2 License.

Copyright (c) 2012 Plataformatec

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
