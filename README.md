# Ecto

Ecto is a domain specific language for writing queries and interacting with databases in Elixir. Here is an example:

```elixir
defmodule Repo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres

  def url do
    "ecto://postgres:postgres@localhost/ecto_simple"
  end
end

defmodule Weather do
  use Ecto.Model

  queryable "weather" do
    field :city,    :string
    field :temp_lo, :integer
    field :temp_hi, :integer
    field :prcp,    :float, default: 0.0
  end
end

defmodule Simple do
  import Ecto.Query

  def sample_query do
    query = from w in Weather,
          where: w.prcp > 0 or w.prcp == nil,
         select: w
    Repo.all(query)
  end
end
```

## Usage

Add Ecto as a dependency in your `mix.exs` file. If you are using PostgreSQL, you will also need the library that Ecto's adapter is using.

```elixir
def deps do
  [ { :ecto, github: "elixir-lang/ecto" },
    { :pgsql, github: "semiocast/pgsql" } ]
end
```

After you are done, run `mix deps.get` in your shell to fetch and compile the dependencies.

## Introduction

When using Ecto, we think about 4 main components:

* Repositories: repositories are wrappers around the database. Via the repository, we can create, update, destroy and query existing entries. A repository needs an adapter and a URL to communicate to the database;
* Entities: entities are data with an identity. They are Elixir records that represent a row in the database;
* Models: models represent behaviour. Validations, callbacks and query handling are all behaviours tied to a model;
* Queries: used to query the database. Queries are written in Elixir syntax and translated to the underlying database engine. Queries are also composable via the `Ecto.Queryable` protocol.

Note how the storage (repositories), the data (entities) and behaviour (models) are decoupled in Ecto. In the following sections, we will describe those components and how they interact with each other. This README will follow the code outlined in the application at [examples/simple](https://github.com/elixir-lang/ecto/tree/master/examples/simple). Please follow the instructions outlined there to get it up and running.

### Repositories

A repository is a wrapper around the database. We can define a repository as follow:

```elixir
defmodule Repo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres

  def url do
    "ecto://postgres:postgres@localhost/ecto_simple"
  end
end
```

Currently we just support the Postgres adapter. The repository is also responsible for defining the url that locates the database. The URL should be in the following format:

    ecto://USERNAME:PASSWORD@HOST/DATABASE

Besides, a set of options can be passed to the adatpter as:

    ecto://USERNAME:PASSWORD@HOST/DATABASE?KEY=VALUE

### Entities

Entities in Elixir are used to represent data. An entity can defined as follow:

```elixir
defmodule Weather.Entity do
  use Ecto.Entity

  field :city,    :string
  field :temp_lo, :integer
  field :temp_hi, :integer
  field :prcp,    :float, default: 0.0
end
```

Since entities are records, all the record functionality is available:

```elixir
weather = Weather.Entity.new
weather.temp_lo = 30
weather.temp_lo #=> 30
```

However, entities bring extra functionalities on top of records. First of all, all entities have an id field, with type integer, used as primary key:

```elixir
weather = Weather.Entity.new(id: 13)
weather.id #=> 13
weather.primary_key #=> 13
```

Entities also provide casting shortcuts and support for associations which we are going to explore next.

#### Types and casting

As seen above, when defining each entity field, a type needs to be given. Those types are specific to Ecto and must be one of:

* `:integer`
* `:float`
* `:binary` - for binaries;
* `:string` - for utf-8 encoded binaries;
* `:list`
* `:datetime`
* `:virtual` - virtual types can have any value and they are not sent to the database;

When manipulating the entity via the record functions, it is responsobility of the developer to ensure the fields are cast to the proper value. For example:

```elixir
weather = Weather.Entity.new(temp_lo: "0")
weather.temp_lo #=> "0"
```

As we will see later, Ecto will only validate the types when a query is being prepared to be sent to the database. So if you attempt to persist the entity above, an error will be raised.

**Yet to be implemented:** since in many applications it is common to receive attributes in a string format and then cast those attributes, Ecto adds an `assign` function to entities:

```elixir
weather = Weather.Entity.assign(temp_lo: "0")
weather.temp_lo #=> 0.0
```

`assign` is also available for updates:

```elixir
weather = Weather.Entity.new(temp_lo: 23.0)
weather = weather.assign(temp_lo: "25.2")
weather.temp_lo #=> 25.2
```
In general, when receiving data from external sources, `assign` is the function recommended to be used.

#### Associations

The entity also supports associations. The supported associations macros are `belongs_to`, `has_one` and `has_many`. While those are defined in the entity, we need to understand a bit more about models in Ecto before going deep into associations.

### Models

Entities in Ecto are simply data. All the behaviour exists in the model which is nothing more than an Elixir module. Ecto provides many convenience functions that makes it easy to implement common model functionality, like callbacks and validations. The functionalities provided by `Ecto.Model` are:

* `Ecto.Model.Queryable` - provides the API necessary to generate queries;
* `Ecto.Model.Callbacks` - to be implemented;
* `Ecto.Model.Validations` - to be implemented;

By using `Ecto.Model` all the functionality above is included, but you can cherry pick the ones you want to use.

#### Queryable

The most basic functionality in a model is the queryable one. It connects an entity to a database table, allowing us to finally interact with a repository. Given the `Weather.Entity` defined above, we can integrate it into a model as follows:

```elixir
defmodule Weather do
  use Ecto.Model
  queryable "weather", Weather.Entity
end
```

Since this is a common pattern, Ecto allows developers to define an entity inlined in a model. We can bundle the `Weather` and `Weather.Entity` modules together as follows:

```elixir
defmodule Weather do
  use Ecto.Model

  queryable "weather" do
    field :city,    :string
    field :temp_lo, :integer
    field :temp_hi, :integer
    field :prcp,    :float, default: 0.0
  end
end
```

This compact model/entity definition is the preferred format (unless you need a decoupled entity) and will be format used from now on. The model also defines both `Weather.new/1` and `Weather.assign/1` functions as shortcuts that simply delegate to `Weather.Entity`:

```elixir
weather = Weather.new(temp_lo: 0, temp_hi: 23)
Weather.Entity[temp_lo: 0, temp_hi: 23]
```

A repository in Elixir only works with queryable structures. Since we have defined our model as a queryable structure, we can finally interact with the repository:

```elixir
weather = Weather.new(temp_lo: 0, temp_hi: 23)
Repo.create(weather)
```

After persisting `weather` to the database, it will return a new copy of weather with the primary key (the `id`) set. We can use this value to read an entity back from the repository:

```elixir
# Get the entity back
weather = Repo.get Weather, 1
#=> Weather.Entity[id: 1, ...]

# Update it
weather = weather.temp_lo(10)
Repo.update(weather)
#=> :ok

# Delete it
Repo.delete(weather)
```

Notice how the storage (repository), the data (entity) and the behaviour (model) are decoupled, with the model acting as a thin layer connecting the repository and the data. This provides many benefits:

* By containing just data, we guarantee that entities are light-weight, serializable structures. In many languages, the entities are represented by large, complex objects, with entwined state transactions;
* By providing behaviour in modules, they are easy to compose (it is a matter of composing functions). You can easily have different entities sharing the same set of validations. Or the same entity being controlled by a different set of validations and rules on different parts of the application. For example, a Weather entity may require a different set of validations and data integrity rules depending on the role of the user manipulating the data;
* By concerning only with storage, operations on the repository are simple and fast. You control the steps your data pass through before entering the repository. We don't pollute the repository with unecessary overhead, providing straight-forward and performant access to storage;

For example, after the remaining model functionality is added, this is how an `update` ection in a REST endpoint could look like:

```elixir
def update(id, params) do
  weather = Repo.get(Weather, id).update(params)

  case Weather.validate(weather) do
    :ok    -> json weather: Repo.create(weather)
    errors -> json errors: errors
  end
end
```

#### Validations

To be implemented.

#### Callbacks

To be implemented.

### Query

To be written.

## Other topics

### Associations

To be written.

### OTP integration

To be written.

## Contributing

Ecto is on the bleeding edge of Elixir so the latest master build is most likely needed, see [Elixir's README](https://github.com/elixir-lang/elixir) on how to build from source.

To contribute you need to compile Ecto from source and test it:

```
$ git clone https://github.com/elixir-lang/ecto.git
$ cd ecto
$ mix test
```

If you are contributing to the Postgres adapter you need to run the integration tests for the adapter (it is a good idea to run the integration tests even if you are not contributing to the adapter). You need a Postgres user with username `postgres` and password `postgres` or with trust authentication. To run the tests the `MIX_ENV` environment variable needs to be set to `pg` when running the tests. To run only the integration tests: `MIX_ENV=pg mix test` or to run all tests: `MIX_ENV=all mix test`.

## Examples

There are example applications in the `examples/` directory.

## License

Copyright 2012-2013 Elixir Lang.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
