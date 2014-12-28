# Ecto

[![Build Status](https://travis-ci.org/elixir-lang/ecto.png?branch=master)](https://travis-ci.org/elixir-lang/ecto)
[![Inline docs](http://inch-ci.org/github/elixir-lang/ecto.svg?branch=master&style=flat)](http://inch-ci.org/github/elixir-lang/ecto)

Ecto is a domain specific language for writing queries and interacting with databases in Elixir. Here is an example:

```elixir
defmodule Repo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres

  def conf do
    # The scheme can be anything, "ecto" is just an example
    parse_url "ecto://postgres:postgres@localhost/ecto_simple"
  end
end

defmodule Weather do
  use Ecto.Model

  schema "weather" do
    field :city     # Defaults to type :string
    field :temp_lo, :integer
    field :temp_hi, :integer
    field :prcp,    :float, default: 0.0
  end
end

defmodule Simple do
  import Ecto.Query

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

Add Ecto as a dependency in your `mix.exs` file. If you are using PostgreSQL, you will also need the library that Ecto's PostgreSQL adapter is using.

```elixir
defp deps do
  [{:postgrex, ">= 0.0.0"},
   {:ecto, "~> 0.3.0"}]
end
```

You should also update your applications list to include both projects:

```elixir
def application do
  [applications: [:postgrex, :ecto]]
end
```

After you are done, run `mix deps.get` in your shell to fetch the dependencies.

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
$ mix test
```

If you are contributing to the Postgres adapter you need to run the integration tests for the adapter (it is a good idea to run the integration tests even if you are not contributing to the adapter). You need a Postgres user with username `postgres` and password `postgres` or with trust authentication. To run the tests the `MIX_ENV` environment variable needs to be set to `pg` when running the tests. To run only the integration tests: `MIX_ENV=pg mix test` or to run all tests: `MIX_ENV=all mix test`.

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
