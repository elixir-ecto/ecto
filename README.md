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
    { :pgsql, github: "ericmj/pgsql", branch: "elixir" } ]
end
```

After you are done, run `mix deps.get` in your shell to fetch and compile the dependencies.

## Important links

* [Mailing list](https://groups.google.com/forum/#!forum/elixir-ecto)
* [Documentation](http://elixir-lang.org/docs/ecto)
* [Examples](https://github.com/elixir-lang/ecto/tree/master/examples)

## Introduction

When using Ecto, we think about 4 main components:

* [Repositories](http://elixir-lang.org/docs/ecto/Ecto.Repo.html): repositories are wrappers around the database. Via the repository, we can create, update, destroy and query existing entries. A repository needs an adapter and a URL to communicate to the database;
* [Entities](http://elixir-lang.org/docs/ecto/Ecto.Entity.html): entities are data with an identity. They are Elixir records that represent a row in the database;
* [Models](http://elixir-lang.org/docs/ecto/Ecto.Model.html): models represent behaviour. Validations, callbacks and query handling are all behaviours tied to a model;
* [Queries](http://elixir-lang.org/docs/ecto/Ecto.Query.html): written in Elixir syntax, queries are used to retrieve information from a given repository. Queries in Ecto are secure, avoiding common problems like SQL Injetion, and also type-safe. Queries are also composable via the `Ecto.Queryable` protocol.

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

Each repository in Ecto defines a `start_link/0` function that needs to be invoked before using the repository. In general, this function is not called directly, but via the supervisor chain, as shown [in the simple example](https://github.com/elixir-lang/ecto/tree/master/examples/simple):

```elixir
defmodule Simple.App do
  use Application.Behaviour

  def start(_type, _args) do
    Simple.Sup.start_link
  end
end

defmodule Simple.Sup do
  use Supervisor.Behaviour

  def start_link do
    :supervisor.start_link({ :local, __MODULE__ }, __MODULE__, [])
  end

  def init([]) do
    tree = [ worker(Repo, []) ]
    supervise(tree, strategy: :one_for_all)
  end
end
```

You can read more about [the Repository API in the docs](http://elixir-lang.org/docs/ecto/Ecto.Repo.html).

### Entities

Entities in Ecto (docs) are used to represent data. An entity can defined as follow:

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
* `:boolean`
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

Entities in Ecto are simply data. All the behaviour exists in models which is nothing more than an Elixir module. Ecto provides many convenience functions that makes it easy to implement common model functionality, like callbacks and validations. The functionalities provided by `Ecto.Model` are:

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

For example, after the remaining model functionality is added, this is how an `update` action in a REST endpoint could look like:

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

Last but not least, Ecto allows you to write queries in Elixir and send them to the repository, which translates them to the underlying database. Let's see an example:

```elixir
import Ecto.Query, only: [from: 2]

query = from w in Weather,
      where: w.prcp > 0 or w.prcp == nil,
     select: w

Repo.all(query)
```

Queries are defined and extended via the `from` macro. The supported keywords are: `:where`, `:order_by`, `:offset`, `:limit`, `:group_by`, `:having`, `:join` and `:select`. For associations we support `:preload`. Although we used `:select` above, it is optional and it defaults to the entity associated to the model being queries.

In the previous section, we have defined our model as queryable. This is what allows our model to be used in the query as: `from w in Weather`. The right-hand side of `in` must implement the `Ecto.Queryable`, which is done automatically for models that use the queryable feature.

Since queries also implement `Ecto.Queryable`, we can compose queries:

```elixir
query = from w in Weather,
      where: w.prcp > 0 or w.prcp == nil

Repo.all(from q in query, limit: 30)
```

When writing a query, you are inside Ecto's query syntax. In order to access external values or invoke functions, you need to use the `^` operator, which is overloaded by Ecto:

```elixir
def min_prcp(min) do
  from w in Weather, where: w.prcp > ^min or w.prcp == nil
end
```

This comes with the extra benefit that queries in Ecto can easily access database functions. For example, `upcase`, `downcase`, `pow` are all available inside Ecto query syntax and are sent directly to the database. You can see the full list of supported functions at [`Ecto.Query.API`](http://elixir-lang.org/docs/ecto/Ecto.Query.API.html).

Finally, notice that queries in Ecto must be type-safe. The following example will fail:

```elixir
Repo.all(from w in Weather, where: w.prcp == "oops")
```

with the following error message:

```elixir
** (Ecto.TypeCheckError) the following expression does not type check:

    &0.prcp() == "foo"

Allowed types for ==/2:

    number == number
    var == var
    nil == _
    _ == nil

Got: float == string
```

The error message is saying that, the database operator `==/2` can compare numbers with numbers, be them integer or floats, it can compare any value with other value of the same type (`var == var`), and it can compare any other value with `nil`.

You can find more about queries and the supported keywords in the [`Ecto.Query` module](http://elixir-lang.org/docs/ecto/Ecto.Query.html).

With this, we finish our introduction. The next section goes into more details on how Ecto integrates with OTP, how to use associations and more.

## Other topics

### Associations

Ecto supports defining associations on entities:

```elixir
defmodule Post do
  use Ecto.Model

  queryable "posts" do
    has_many :comments, Comment
  end
end

defmodule Comment do
  use Ecto.Model

  queryable "comments" do
    field :title, :string
    belongs_to :post, Post
  end
end
```

For each association, Ecto defines a function in `Post` to retrieve the association metadata with the associated entity. For example:

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
     select: assoc(p, c)

[post] = Repo.all(query)

post.comments.to_list #=> [Comment.Entity[...], Comment.Entity[...]]
```

Notice we used the `assoc` helper to associate the returned posts and comments while assembling the query results. In many cases, developers simply want to get all posts with all associated comments. For such, Ecto support preloads:

```elixir
posts = Repo.all(from p in Post, preload: [:comments])
hd(posts).comments.to_list #=> [Comment.Entity[...], Comment.Entity[...]]
```

When preloading, differently from `join`, Ecto does a separate query to retrieve all comments associated with the returned posts.

Notice that Ecto does not lazy load associations. While lazily loading associations may sound convenient at first, in the long run it becomes a source of confusion and performance issues. That said, if you call `to_list` in an association that is not currently loaded, Ecto will raise an error:

```elixir
post = Repo.get(Post, 42)
post.comments.to_list #=> ** (Ecto.AssociationNotLoadedError)
```

Besides `has_many`, Ecto also supports `has_one` and `belongs_to` associations. They work similarly, except retrieve the association value is done via `get`, instead of `to_list`:

```elixir
query = from(c in Comment, where: c.id == 42, preload: :post)
[comment] = Repo.all(query)
comment.post.get #=> Post.Entity[...]
```

You can find more information about defining associations and each respective association module [in `Ecto.Entity` docs](http://elixir-lang.org/docs/ecto/Ecto.Entity.html).

### Migrations

Ecto supports now migrations with plain sql.

```elixir
defmodule MyApp.MyMigration do

  def up do
    "CREATE TABLE user(id serial PRIMARY_KEY, username varchar(25))"
  end

  def down do
    "DROP TABLE user"
  end
end
```

now you can execute migration:

```elixir
Ecto.Migrator.up(Repo, 20130906120000, MyApp.MyMigration) == :ok
```

Result must be:

  * `:ok` - When the migrations is executed successfully
  * `:already_up` - The migration is already in the table (returned by migrate_up)
  * `:missing_up` - The migration is not in the table (returned by migrate_down)
  * `{ :error, error :: term }` - Error from the database

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
