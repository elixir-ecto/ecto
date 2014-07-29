# Ecto

[![Build Status](https://travis-ci.org/elixir-lang/ecto.png?branch=master)](https://travis-ci.org/elixir-lang/ecto)

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
          where: w.prcp > 0 or w.prcp == nil,
         select: w
    Repo.all(query)
  end
end
```

## Usage

Add Ecto as a dependency in your `mix.exs` file. If you are using PostgreSQL, you will also need the library that Ecto's PostgreSQL adapter is using.

```elixir
defp deps do
  [{:postgrex, ">= 0.0.0"},
   {:ecto, "~> 0.2.0"}]
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

* [Mailing list](https://groups.google.com/forum/#!forum/elixir-ecto)
* [Documentation](http://elixir-lang.org/docs/ecto)
* [Examples](https://github.com/elixir-lang/ecto/tree/master/examples)

## Introduction

When using Ecto, we think about 3 main components:

* [Repositories](http://elixir-lang.org/docs/ecto/Ecto.Repo.html): repositories are wrappers around the database. Via the repository, we can create, update, destroy and query existing entries. A repository needs an adapter and a URL to communicate to the database;
* [Models](http://elixir-lang.org/docs/ecto/Ecto.Model.html): models is a collection of functionality like the schema, validations and callbacks that can be cherry-picked;
* [Queries](http://elixir-lang.org/docs/ecto/Ecto.Query.html): written in Elixir syntax, queries are used to retrieve information from a given repository. Queries in Ecto are secure, avoiding common problems like SQL Injection, and also type-safe. Queries are also composable via the `Ecto.Queryable` protocol.

Note how the storage (repositories), the data (entities) and behaviour (models) are decoupled in Ecto. In the following sections, we will describe those components and how they interact with each other. This README will follow the code outlined in the application at [examples/simple](https://github.com/elixir-lang/ecto/tree/master/examples/simple). Please follow the instructions outlined there to get it up and running.

### Repositories

A repository is a wrapper around the database. We can define a repository as follow:

```elixir
defmodule Repo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres

  def conf do
    parse_url "ecto://postgres:postgres@localhost/ecto_simple"
  end
end
```

Currently we just support the Postgres adapter. The repository is also responsible for defining the url that locates the database. The URL should be in the following format:

    ecto://USERNAME:PASSWORD@HOST/DATABASE

Besides, a set of options can be passed to the adapter as:

    ecto://USERNAME:PASSWORD@HOST/DATABASE?KEY=VALUE

Each repository in Ecto defines a `start_link/0` function that needs to be invoked before using the repository. In general, this function is not called directly, but via the supervisor chain. In your application, it is very likely you have a `lib/*/supervisor.ex` file. You just need to edit it to start your worker on the supervisor `init/1` function:

```elixir
def init([]) do
  tree = [worker(Repo, [])]
  supervise(tree, strategy: :one_for_all)
end
```

A simple example can be found [in the Ecto git repo](https://github.com/elixir-lang/ecto/tree/master/examples/simple).

You can read more about [the Repository API in the docs](http://elixir-lang.org/docs/ecto/Ecto.Repo.html).

### Models

Models provide different functionality that can be cherry-picked at will. They are:

* [`Ecto.Model.Schema`](http://elixir-lang.org/docs/ecto/Ecto.Model.Schema.html) - defines a model schema so it can be used in queries;
* [`Ecto.Model.Validations`](http://elixir-lang.org/docs/ecto/Ecto.Model.Validations.html) - conveniences for defining module-level validations in models;
* `Ecto.Model.Callbacks` - to be implemented;

By using `Ecto.Model`, you get all of the above:

```elixir
defmodule Weather do
  use Ecto.Model

  # weather is the DB table
  schema "weather" do
    field :city,    :string
    field :temp_lo, :integer
    field :temp_hi, :integer
    field :prcp,    :float, default: 0.0
  end
end
```

By defining a schema, Ecto automatically defines a struct with the schema fields:

```elixir
weather = %Weather{temp_lo: 30}
weather.temp_lo #=> 30
```

The schema also allows the model to interact with a repository:

```elixir
weather = %Weather{temp_lo: 0, temp_hi: 23}
Repo.insert(weather)
```

After persisting `weather` to the database, it will return a new copy of weather with the primary key (the `id`) set. We can use this value to read a struct back from the repository:

```elixir
# Get the struct back
weather = Repo.get Weather, 1
#=> %Weather{id: 1, ...}

# Update it
weather = %{weather | temp_lo: 10}
Repo.update(weather)
#=> :ok

# Delete it
Repo.delete(weather)
```

> NOTE: by using `Ecto.Model`, an `:id` field with type `:integer` is generated by default, which is the primary key of the Model. If you want to use a different type of primary key, you can declare custom `@schema_defaults` in a module, and use that in place of `Ecto.Model`. [Consult the `Ecto.Model.Schema` documentation for usage instructions](http://elixir-lang.org/docs/ecto/Ecto.Model.Schema.html).

Notice how the storage (repository) and the model are decoupled with structs representing data. This provides many benefits:

* By having structs as data, we guarantee they are are light-weight, serializable structures. In many languages, the data is often represented by large, complex objects, with entwined state transactions, which makes serialization particularly hard;
* By providing behaviour in modules, they are easy to compose (it is a matter of composing functions). You can easily have different structs sharing the same set of validations. Or the same struct being controlled by a different set of validations and rules on different parts of the application. For example, the Weather struct may require a different set of validations and data integrity rules depending on the role of the user manipulating the data;
* By concerning only with storage, operations on the repository are simple and fast. You control the steps your data pass through before entering the repository. We don't pollute the repository with unecessary overhead, providing straight-forward and performant access to storage;

Note you can use the `struct/2` function that ships with Elixir to create or update a struct based on dynamic values:

```elixir
fields = [temp_lo: 30]
weather = struct(Weather, fields)
weather.temp_lo #=> 30
weather = struct(weather, temp_lo: 13)
weather.temp_lo #=> 13
```

With this functionality in mind, this is how an `update` action in a REST endpoint could look like:

```elixir
def update(id, params) do
  weather = Repo.get(Weather, id) |> struct(params)

  case Weather.validate(weather) do
    [] ->
      Repo.update(weather)
      json weather: weather
    errors ->
      json errors: errors
  end
end
```

### Query

Last but not least, Ecto allows you to write queries in Elixir and send them to the repository, which translates them to the underlying database. Let's see an example:

```elixir
import Ecto.Query, only: [from: 2]

query = from w in Weather,
      where: w.prcp > 0 or w.prcp == nil,
     select: w

Repo.all(query)
```

Queries are defined and extended with the `from` macro. The supported keywords are:

* `:distinct`
* `:where`
* `:order_by`
* `:offset`
* `:limit`
* `:lock`
* `:group_by`
* `:having`
* `:join`
* `:select` - although we used `:select` above, it is optional and by default it simply returns the model being queried
* `:preload` - used for preloading associations

When writing a query, you are inside Ecto's query syntax. In order to access external values or invoke functions, you need to use the `^` operator, which is overloaded by Ecto:

```elixir
def min_prcp(min) do
  from w in Weather, where: w.prcp > ^min or w.prcp == nil
end
```

This comes with the extra benefit that queries in Ecto can easily access database functions. For example, `upcase`, `downcase`, `pow` are all available inside Ecto query syntax and are sent directly to the database. You can see the full list of supported functions at [`Ecto.Query.API`](http://elixir-lang.org/docs/ecto/Ecto.Query.API.html).

Ecto queries are also composable and type-safe. You can find more info it and the supported keywords in the [`Ecto.Query` module](http://elixir-lang.org/docs/ecto/Ecto.Query.html).

With this, we finish our introduction. The next section goes into more details on other Ecto features, like generators, associations and more.

## Other topics

### Mix tasks and generators

Ecto provides many tasks to help your workflow as well as code generators. You can find all available tasks by typing `mix help` inside a project with Ecto.

Ecto generators will automatically open the generated files if you have `ECTO_EDITOR` set in your environment variable. You can set this variable for different editors as follows:

* Textmate: `mate -a`

### Types and casting

When defining the schema, types need to be given. Those types are specific to Ecto and must be one of:

* `:integer`
* `:float`
* `:boolean`
* `:binary` - for binaries;
* `:string` - for utf-8 encoded binaries;
* `{:array, inner_type}`
* `:datetime`
* `:date`
* `:time`
* `:virtual` - virtual types can have any value and they are not sent to the database;

When manipulating the struct, it is the responsibility of the developer to ensure the fields are cast to the proper value. For example, you can create a weather struct with an invalid value for `temp_lo`:

```elixir
weather = %Weather{temp_lo: "0"}
weather.temp_lo #=> "0"
```

However, if you attempt to persist the struct above, an error will be raised since Ecto validates the types when a query is being prepared to be sent to the database.

### Associations

Ecto supports defining associations on entities:

```elixir
defmodule Post do
  use Ecto.Model

  schema "posts" do
    has_many :comments, Comment
  end
end

defmodule Comment do
  use Ecto.Model

  schema "comments" do
    field :title, :string
    belongs_to :post, Post
  end
end
```

Ecto defines a field for each association:

```elixir
post = Repo.get(Post, 42)
post.comments #=> Ecto.Association.HasMany[...]
```

The association record above provides a couple conveniences. First of all, `post.comments` is a queryable structure, which means we can use it in queries:

```elixir
# Get all comments for the given post
Repo.all(post.comments)

# Build a query on top of the associated comments
query = from c in post.comments, where: c.title != nil
Repo.all(query)
```

Ecto also supports joins with associations:

```elixir
query = from p in Post,
      where: p.id == 42,
  left_join: c in p.comments,
     select: assoc(p, comments: c)

[post] = Repo.all(query)

post.comments.all #=> [%Comment{...}, %Comment{...}]
```

Notice we used the `assoc` helper to associate the returned posts and comments while assembling the query results.

It is easy to see above though that a developer simply wants to get all comments associated to each post. There is no filtering based on the underlying comment. For such, Ecto support preloads:

```elixir
posts = Repo.all(from p in Post, preload: [:comments])
hd(posts).comments.all #=> [%Comment{...}, %Comment{...}]
```

When preloading, Ecto first fetches all posts and then Ecto does a separate query to retrieve all comments associated with the returned posts.

Notice that Ecto does not lazy load associations. While lazily loading associations may sound convenient at first, in the long run it becomes a source of confusion and performance issues. That said, if you call `to_list` in an association that is not currently loaded, Ecto will raise an error:

```elixir
post = Repo.get(Post, 42)
post.comments.all #=> ** (Ecto.AssociationNotLoadedError)
```

Besides `has_many`, Ecto also supports `has_one` and `belongs_to` associations. They work similarly, except retrieving the association value is done via `get`, instead of `all`:

```elixir
query = from(c in Comment, where: c.id == 42, preload: :post)
[comment] = Repo.all(query)
comment.post.get #=> %Post{...}
```

You can find more information about defining associations and each respective association module [in `Ecto.Model.Schema` docs](http://elixir-lang.org/docs/ecto/Ecto.Model.Schema.html).

### Migrations

Ecto supports migrations with plain SQL. In order to generate a new migration you first need to a define a `priv/0` function inside your repository pointing to a directory that will keep repo data. We recommend it to be placed inside the `priv` in your application directory:

```elixir
defmodule Repo do
  use Ecto.Repo, adapter: Ecto.Adapters.Postgres

  def priv do
    app_dir(:YOUR_APP_NAME, "priv/repo")
  end
end
```

Where `:YOUR_APP_NAME` is your application name (as in the `mix.exs` file). Now a migration can be generated with:

    $ mix ecto.gen.migration Repo create_posts

This will create a new file inside `priv/repo/migrations` with the following contents:

```elixir
defmodule Repo.CreatePosts do
  use Ecto.Migration

  def up do
    [ "CREATE TABLE IF NOT EXISTS migrations_test(id serial primary key, name text)",
      "INSERT INTO migrations_test (name) VALUES ('inserted')" ]
  end

  def down do
    "DROP TABLE migrations_test"
  end
end
```

Simply write the SQL commands for updating the database (`up`) and for rolling it back (`down`) and you are ready to go! To run a single command return a string, to run multiple return a list of strings.

Note the generated file (and all migration files) starts with a timestamp, which identifies the migration version. By running migrations, a `schema_migrations` table will be created in your database to keep which migrations are "up" (already executed) and which ones are "down".

Migrations can be applied and rolled back with the mix tasks `ecto.migrate` and `ecto.rollback`. See the documentation for `Mix.Tasks.Ecto.Migrate` and `Mix.Tasks.Ecto.Rollback` for more in depth instructions.

To run all pending migrations:

    $ mix ecto.migrate Repo

Roll back all applied migrations:

    $ mix ecto.rollback Repo --all

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
