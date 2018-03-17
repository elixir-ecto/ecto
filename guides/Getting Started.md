# Getting Started

This guide is an introduction to [Ecto](https://github.com/elixir-lang/ecto),
the database wrapper and query generator for Elixir. Ecto provides a
standardised API and a set of abstractions for talking to all the different
kinds of databases, so that Elixir developers can query whatever database
they're using by employing similar constructs.

In this guide, we're going to learn some basics about Ecto, such as creating,
reading, updating and destroying records from a PostgreSQL database. If you want
to see the code from this guide, you can view it [at ecto/examples/friends on GitHub](https://github.com/elixir-lang/ecto/tree/master/examples/friends).

**This guide will require you to have setup PostgreSQL beforehand.**

## Adding Ecto to an application

To start off with, we'll generate a new Elixir application by running this command:

```
mix new friends --sup
```

The `--sup` option ensures that this application has [a supervision tree](http://elixir-lang.org/getting-started/mix-otp/supervisor-and-application.html), which we'll need for Ecto a little later on.

To add Ecto to this application, there are a few steps that we need to take. The first step will be adding Ecto and a driver called Postgrex to our `mix.exs` file, which we'll do by changing the `deps` definition in that file to this:

```elixir
defp deps do
  [{:ecto, "~> 2.0"},
   {:postgrex, "~> 0.11"}]
end
```

Ecto provides the common querying API, but we need the Postgrex driver installed too, as that is what Ecto uses to speak in terms a PostgreSQL database can understand. Ecto talks to its own `Ecto.Adapters.Postgres` module, which then in turn talks to the `postgrex` package to talk to PostgreSQL.

To install these dependencies, we will run this command:

```
mix deps.get
```

The Postgrex application will receive queries from Ecto and execute them
against our database. If we didn't do this step, we wouldn't be able to do any
querying at all.

That's the first two steps taken now. We have installed Ecto and Postgrex as
dependencies of our application. We now need to setup some configuration for
Ecto so that we can perform actions on a database from within the
application's code.

We can set up this configuration by running this command:

```
mix ecto.gen.repo -r Friends.Repo
```

This command will generate the configuration required to connect to a database. The first bit of configuration is in `config/config.exs`:

```elixir
config :friends, Friends.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "friends_repo",
  username: "user",
  password: "pass",
  hostname: "localhost"
```

**NOTE**: Your PostgreSQL database may be setup to

 - not require a username and password. If the above configuration doesn't work, try removing the username and password fields, or setting them both to "postgres".
 - be running on a non-standard port. The default port is `5432`. You can specify your specific port by adding it to the config: e.g. `port: 15432`.

This configures how Ecto will connect to our database, called "friends". Specifically, it configures a "repo". More information about [Ecto.Repo can be found in its documentation](https://hexdocs.pm/ecto/Ecto.Repo.html).

The `Friends.Repo` module is defined in `lib/friends/repo.ex` by our `mix ecto.gen.repo` command:

```elixir
defmodule Friends.Repo do
  use Ecto.Repo, otp_app: :friends
end
```

This module is what we'll be using to query our database shortly. It uses the `Ecto.Repo` module, and the `otp_app` tells Ecto which Elixir application it can look for database configuration in. In this case, we've specified that it is the `:friends` application where Ecto can find that configuration and so Ecto will use the configuration that was set up in `config/config.exs`.

The final piece of configuration is to setup the `Friends.Repo` as a supervisor within the application's supervision tree, which we can do in `lib/friends/application.ex` (or `lib/friends.ex` for elixir versions `< 1.4.0`), inside the `start/2` function:

`Elixir < 1.5.0`:
```elixir
def start(_type, _args) do
  import Supervisor.Spec

  children = [
    supervisor(Friends.Repo, []),
  ]

  ...
```

`Elixir >= 1.5.0`:
```elixir
def start(_type, _args) do
  import Supervisor.Spec

  children = [
    Friends.Repo,
  ]

  ...
```

This piece of configuration will start the Ecto process which receives and executes our application's queries. Without it, we wouldn't be able to query the database at all!

There's one final bit of configuration that we'll need to add ourselves, since the generator does not add it. Underneath the configuration in `config/config.exs`, add this line:

```elixir
config :friends, ecto_repos: [Friends.Repo]
```

This tells our application about the repo, which will allow us to run commands such as `mix ecto.create` very soon.

We've now configured our application so that it's able to make queries to our database. Let's now create our database, add a table to it, and then perform some queries.

## Test Environment Setup

The test environment setup is described [here](Testing%20with%20Ecto.md).

## Setting up the database

To be able to query a database, it first needs to exist. We can create the database with this command:

```
mix ecto.create
```

If the database has been created successfully, then you will see this message:

```
The database for Friends.Repo has been created.
```

**NOTE:** If you get an error, you should try changing your configuration in `config/config.exs`, as it may be an authentication error.

A database by itself isn't very queryable, so we will need to create a table within that database. To do that, we'll use what's referred to as a _migration_. If you've come from Active Record (or similar), you will have seen these before. A migration is a single step in the process of constructing your database.

Let's create a migration now with this command:

```
mix ecto.gen.migration create_people
```

This command will generate a brand new migration file in `priv/repo/migrations`, which is empty by default:

```elixir
defmodule Friends.Repo.Migrations.CreatePeople do
  use Ecto.Migration

  def change do

  end
end
```

Let's add some code to this migration to create a new table called "people", with a few columns in it:

```elixir
defmodule Friends.Repo.Migrations.CreatePeople do
  use Ecto.Migration

  def change do
    create table(:people) do
      add :first_name, :string
      add :last_name, :string
      add :age, :integer
    end
  end
end
```

This new code will tell Ecto to create a new table called `people`, and add three new fields: `first_name`, `last_name` and `age` to that table. The types of these fields are `string` and `integer`. (The different types that Ecto supports are covered in the [Ecto.Schema](https://hexdocs.pm/ecto/Ecto.Schema.html) documentation.)

**NOTE**: The naming convention for tables in Ecto databases is to use a pluralized name.

To run this migration and create the `people` table in our database, we will run this command:

```
mix ecto.migrate
```

If we found out that we made a mistake in this migration, we could run `mix ecto.rollback` to undo the changes in the migration. We could then fix the changes in the migration and run `mix ecto.migrate` again. If we ran `mix ecto.rollback` now, it would delete the table that we just created.

We now have a table created in our database. The next step that we'll need to do is to create the schema.

## Creating the schema

The schema is an Elixir representation of data from our database. Schemas are commonly associated with a database table, however they can be associated with a database view as well.

Let's create the schema within our application at `lib/friends/person.ex`:

```elixir
defmodule Friends.Person do
  use Ecto.Schema

  schema "people" do
    field :first_name, :string
    field :last_name, :string
    field :age, :integer
  end
end
```

This defines the schema from the database that this schema maps to. In this case, we're telling Ecto that the `Friends.Person` schema maps to the `people` table in the database, and the `first_name`, `last_name` and `age` fields in that table. The second argument passed to `field` tells Ecto how we want the information from the database to be represented in our schema.

We've called this schema `Person` because the naming convention in Ecto for schemas is a singularized name.

We can play around with this schema in an IEx session by starting one up with `iex -S mix` and then running this code in it:

```elixir
person = %Friends.Person{}
```

This code will give us a new `Friends.Person` struct, which will have `nil` values for all the fields. We can set values on these fields by generating a new struct:

```elixir
person = %Friends.Person{age: 28}
```

Or with syntax like this:

```elixir
%{person | age: 28}
```

We can retrieve values using this syntax:

```elixir
person.age # => 28
```

Let's take a look at how we can insert data into the database.

## Inserting data

We can insert a new record into our `people` table with this code:

```elixir
person = %Friends.Person{}
Friends.Repo.insert(person)
```

To insert the data into our database, we call `insert` on `Friends.Repo`, which is the module that uses Ecto to talk to our database. This function tells Ecto that we want to insert a new `Friends.Person` record into the database corresponding with `Friends.Repo`. The `person` struct here represents the data that we want to insert into the database.

A successful insertion will return a tuple, like so:

```elixir
{:ok,
 %Friends.Person{__meta__: #Ecto.Schema.Metadata<:loaded>, age: nil,
  first_name: nil, id: 1, last_name: nil}}
```

The `:ok` atom can be used for pattern matching purposes to ensure that the insertion succeeds. A situation where the insertion may not succeed is if you have a constraint on the database itself. For instance, if the database had a unique constraint on a field called `email` so that an email can only be used for one person record, then the insertion would fail.

You may wish to pattern match on the tuple in order to refer to the record inserted into the database:

```elixir
{:ok, person} = Friends.Repo.insert person
```

## Validating changes

In Ecto, you may wish to validate changes before they go to the database. For instance, you may wish that a person has both a first name and a last name before a record can be entered into the database. For this, Ecto has [_changesets_](https://hexdocs.pm/ecto/Ecto.Changeset.html).

Let's add a changeset to our `Friends.Person` module inside `lib/friends/person.ex` now:

```elixir
def changeset(person, params \\ %{}) do
  person
  |> Ecto.Changeset.cast(params, [:first_name, :last_name, :age])
  |> Ecto.Changeset.validate_required([:first_name, :last_name])
end
```

This changeset takes a `person` and a set of params, which are to be the changes to apply to this person. The `changeset` function first casts the `first_name`, `last_name` and `age` keys from the parameters passed in to the changeset. Casting tells the changeset what parameters are allowed to be passed through in this changeset, and anything not in the list will be ignored.

On the next line, we call `validate_required` which says that, for this changeset, we expect `first_name` and `last_name` to have values specified. Let's use this changeset to attempt to create a new record without a `first_name` and `last_name`:

```elixir
person = %Friends.Person{}
changeset = Friends.Person.changeset(person, %{})
Friends.Repo.insert(changeset)
```

On the first line here, we get a struct from the `Friends.Person` module. We know what that does, because we saw it not too long ago. On the second line we do something brand new: we define a changeset. This changeset says that on the specified `person` object, we're looking to make some changes. In this case, we're not looking to change anything at all.

On the final line, rather than inserting the `person`, we insert the `changeset`. The `changeset` knows about the `person`, the changes and the validation rules that must be met before the data can be entered into the database. When this third line runs, we'll see this:

```elixir
{:error,
 #Ecto.Changeset<action: :insert, changes: %{},
  errors: [first_name: "can't be blank", last_name: "can't be blank"],
  data: #Friends.Person<>, valid?: false>}
```

Just like the last time we did an insertion, this returns a tuple. This time however, the first element in the tuple is `:error`, which indicates something bad happened. The specifics of what happened are included in the changeset which is returned. We can access these by doing some pattern matching:

```elixir
{:error, changeset} = Friends.Repo.insert(changeset)
```

Then we can get to the errors by doing `changeset.errors`:

```elixir
[first_name: "can't be blank", last_name: "can't be blank"]
```

And we can ask the changeset itself it is valid, even before doing an insertion:

```elixir
changeset.valid?
#=> false
```

Since this changeset has errors, no new record was inserted into the `people`
table.

Let's try now with some valid data.

```elixir
person = %Friends.Person{}
changeset = Friends.Person.changeset(person, %{first_name: "Ryan", last_name: "Bigg"})
```

We start out here with a normal `Friends.Person` struct. We then create a changeset for that `person` which has a `first_name` and a `last_name` parameter specified. At this point, we can ask the changeset if it has errors:

```elixir
changeset.errors
#=> []
```

And we can ask if it's valid or not:

```elixir
changeset.valid?
#=> true
```

The changeset does not have errors, and is valid. Therefore if we try to insert this changeset it will work:

```elixir
Friends.Repo.insert(changeset)
#=> {:ok,
     %Friends.Person{__meta__: #Ecto.Schema.Metadata<:loaded>, age: nil,
      first_name: "Ryan", id: 3, last_name: "Bigg"}}
```


Due to `Friends.Repo.insert` returning a tuple, we can use a `case` to determine different code paths depending on what happens:

```elixir
case Friends.Repo.insert(changeset) do
  {:ok, person} ->
    # do something with person
  {:error, changeset} ->
    # do something with changeset
end
```

**NOTE:** `changeset.valid?` will not check constraints (such as `uniqueness_constraint`). For that, you will need to attempt to do an insertion and check for errors from the database. It's for this reason it's best practice to try inserting data and validate the returned tuple from `Friends.Repo.insert` to get the correct errors, as prior to insertion the changeset will only contain validation errors from the application itself.

If the insertion of the changeset succeeds, then you can do whatever you wish with the `person` returned in that result. If it fails, then you have access to the changeset and its errors. In the failure case, you may wish to present these errors to the end user. The errors in the changeset are a keyword list that looks like this:


```elixir
[first_name: {"can't be blank", []},
 last_name: {"can't be blank", []}]
```

The first element of the tuple is the validation message, and the second element is a keyword list of options for the validation message. The `validate_required/3` validations don't return any options, but other methods such as `validate_length/3` do. Imagine that we had a field called `bio` that we were validating, and that field has to be longer than 15 characters. This is what would be returned:


```elixir
[first_name: {"can't be blank", []},
 last_name: {"can't be blank", []},
 bio: {"should be at least %{count} characters", [count: 15]}]
```

To display these error messages in a human friendly way, we can use `Ecto.Changeset.traverse_errors/2`:

```elixir
traverse_errors(changeset, fn {msg, opts} ->
  Enum.reduce(opts, msg, fn {key, value}, acc ->
    String.replace(acc, "%{#{key}}", to_string(value))
  end)
end)
```

This will return the following for the errors shown above:

```elixir
%{
  first_name: ["can't be blank"],
  last_name: ["can't be blank"],
  bio: ["should be at least 15 characters"],
}
```

One more final thing to mention here: you can trigger an exception to be thrown by using `Friends.Repo.insert!/2`. If a changeset is invalid, you will see an `Ecto.InvalidChangesetError` exception. Here's a quick example of that:

```
Friends.Repo.insert! Friends.Person.changeset(%Friends.Person{}, %{first_name: "Ryan"})

** (Ecto.InvalidChangesetError) could not perform insert because changeset is invalid.

* Changeset changes

%{first_name: "Ryan"}

* Changeset params

%{"first_name" => "Ryan"}

* Changeset errors

[last_name: "can't be blank"]

    lib/ecto/repo/schema.ex:111: Ecto.Repo.Schema.insert!/4
```

This exception shows us the changes from the changeset, and how the changeset is invalid. This can be useful if you want to insert a bunch of data and then have an exception raised if that data is not inserted correctly at all.

Now that we've covered inserting data into the database, let's look at how we can pull that data back out.

## Our first queries

Querying a database requires two steps in Ecto. First, we must construct the query and then we must execute that query against the database by passing the query to the repository. Before we do this, let's re-create the database for our app and setup some test data. To re-create the database, we'll run these commands:

```
mix ecto.drop
mix ecto.create
mix ecto.migrate
```

Then to create the test data, we'll run this in an `iex -S mix` session:

```elixir
people = [
  %Friends.Person{first_name: "Ryan", last_name: "Bigg", age: 28},
  %Friends.Person{first_name: "John", last_name: "Smith", age: 27},
  %Friends.Person{first_name: "Jane", last_name: "Smith", age: 26},
]

Enum.each(people, fn (person) -> Friends.Repo.insert(person) end)
```

This code will create three new people in our database, Ryan, John and Jane. Note here that we could've used a changeset to validate the data going into the database, but the choice was made not to use one.

We'll be querying for these people in this section. Let's jump in!

### Fetching a single record

Let's start off with fetching just one record from our `people` table:

```elixir
Friends.Person |> Ecto.Query.first
```

That code will generate an `Ecto.Query`, which will be this:

```
#Ecto.Query<from p in Friends.Person, order_by: [asc: p.id], limit: 1>
```

The code between the angle brackets `<...>` here shows the Ecto query which has been constructed. We could construct this query ourselves with almost exactly the same syntax:

```elixir
require Ecto.Query
Ecto.Query.from p in Friends.Person, order_by: [asc: p.id], limit: 1
```

We need to `require Ecto.Query` here to enable the macros from that module. Then it's a matter of calling the `from` function from `Ecto.Query` and passing in the code from between the angle brackets. As we can see here, `Ecto.Query.first` saves us from having to specify the `order` and `limit` for the query.

To execute the query that we've just constructed, we can call `Friends.Repo.one`:

```elixir
Friends.Person |> Ecto.Query.first |> Friends.Repo.one
```

The `one` function retrieves just one record from our database and returns a new struct from the `Friends.Person` module:

```elixir
%Friends.Person{__meta__: #Ecto.Schema.Metadata<:loaded>, age: 28,
 first_name: "Ryan", id: 1, last_name: "Bigg"}
```

Similar to `first`, there is also `last`:

```elixir
Friends.Person |> Ecto.Query.last |> Friends.Repo.one
#=> %Friends.Person{__meta__: #Ecto.Schema.Metadata<:loaded>, age: 26,
     first_name: "Jane", id: 3, last_name: "Smith"}
 ```

The `Ecto.Repo.one` function will only return a struct if there is one record in the
result from the database. If there is more than one record returned, an
`Ecto.MultipleResultsError` exception will be thrown. Some code that would
cause that issue to happen is:

```elixir
Friends.Person |> Friends.Repo.one
```

We've left out the `Ecto.Query.first` here, and so there is no `limit` or `order` clause applied to the executed query. We'll see the executed query in the debug log:

```
[timestamp] [debug] SELECT p0."id", p0."first_name", p0."last_name", p0."age" FROM "people" AS p0 [] OK query=1.8ms
```

Then immediately after that, we will see the `Ecto.MultipleResultsError` exception:

```
** (Ecto.MultipleResultsError) expected at most one result but got 3 in query:

from p in Friends.Person

    lib/ecto/repo/queryable.ex:67: Ecto.Repo.Queryable.one/4
```

This happens because Ecto doesn't know what one record out of all the records
returned that we want. Ecto will only return a result if we are explicit in
our querying about which result we want.

If there is no record which matches the query, `one` will return `nil`.

### Fetching all records

To fetch all records from the schema, Ecto provides the `all` function:

```elixir
Friends.Person |> Friends.Repo.all
```

This will return a `Friends.Person` struct representation of all the records that currently exist within our `people` table:

```elixir
[%Friends.Person{__meta__: #Ecto.Schema.Metadata<:loaded>, age: 28,
  first_name: "Ryan", id: 1, last_name: "Bigg"},
 %Friends.Person{__meta__: #Ecto.Schema.Metadata<:loaded>, age: 27,
  first_name: "John", id: 2, last_name: "Smith"},
 %Friends.Person{__meta__: #Ecto.Schema.Metadata<:loaded>, age: 26,
  first_name: "Jane", id: 3, last_name: "Smith"}]
```

### Fetch a single record based on ID

To fetch a record based on its ID, you use the `get` function:

```elixir
Friends.Person |> Friends.Repo.get(1)
%Friends.Person{__meta__: #Ecto.Schema.Metadata<:loaded>, age: 28,
 first_name: "Ryan", id: 1, last_name: "Bigg"}
```

### Fetch a single record based on a specific attribute

If we want to get a record based on something other than the `id` attribute, we can use `get_by`:

```elixir
 Friends.Person |> Friends.Repo.get_by(first_name: "Ryan")
 %Friends.Person{__meta__: #Ecto.Schema.Metadata<:loaded>, age: 28,
  first_name: "Ryan", id: 1, last_name: "Bigg"}
```

### Filtering results

If we want to get multiple records matching a specific attribute, we can use `where`:

```elixir
Friends.Person |> Ecto.Query.where(last_name: "Smith") |> Friends.Repo.all
```

```elixir
[%Friends.Person{__meta__: #Ecto.Schema.Metadata<:loaded>, age: 27,
  first_name: "John", id: 2, last_name: "Smith"},
 %Friends.Person{__meta__: #Ecto.Schema.Metadata<:loaded>, age: 26,
  first_name: "Jane", id: 3, last_name: "Smith"}]
```

If we leave off the `Friends.Repo.all` on the end of this, we will see the query Ecto generates:

```
#Ecto.Query<from p in Friends.Person, where: p.last_name == "Smith">
```

We can also use this query syntax to fetch these same records:

```elixir
Ecto.Query.from(p in Friends.Person, where: p.last_name == "Smith") |> Friends.Repo.all
```

One important thing to note with both query syntaxes is that they require variables to be pinned, using the pin operator (`^`). Otherwise, this happens:

```elixir
last_name = "Smith"
Friends.Person |> Ecto.Query.where(last_name: last_name) |> Friends.Repo.all
```

```
** (Ecto.Query.CompileError) variable `last_name` is not a valid query expression.
  Variables need to be explicitly interpolated in queries with ^
             expanding macro: Ecto.Query.where/2
             iex:1: (file)
    (elixir) expanding macro: Kernel.|>/2
             iex:1: (file)
```

The same will happen in the longer query syntax too:

```elixir
Ecto.Query.from(p in Friends.Person, where: p.last_name == last_name) |> Friends.Repo.all
```

```
** (Ecto.Query.CompileError) variable `last_name` is not a valid query expression.
  Variables need to be explicitly interpolated in queries with ^
             expanding macro: Ecto.Query.where/3
             iex:1: (file)
             expanding macro: Ecto.Query.from/2
             iex:1: (file)
    (elixir) expanding macro: Kernel.|>/2
             iex:1: (file)
```

To get around this, we use the pin operator (`^`):

```elixir
last_name = "Smith"
Friends.Person |> Ecto.Query.where(last_name: ^last_name) |> Friends.Repo.all
```

Or:

```elixir
last_name = "Smith"
Ecto.Query.from(p in Friends.Person, where: p.last_name == ^last_name) |> Friends.Repo.all
```

The pin operator instructs the query builder to use parameterised SQL queries protecting against SQL injection.

### Composing Ecto queries

Ecto queries don't have to be built in one spot. They can be built up by calling `Ecto.Query` functions on existing queries. For instance, if we want to find all people with the last name "Smith", we can do:

```elixir
query = Friends.Person |> Ecto.Query.where(last_name: "Smith")
```

If we want to scope this down further to only people with the first name of "Jane", we can do this:

```elixir
query = query |> Ecto.Query.where(first_name: "Jane")
```

Our query will now have two `where` clauses in it:

```
#Ecto.Query<from p in Friends.Person, where: p.last_name == "Smith",
 where: p.first_name == "Jane">
```

This can be useful if you want to do something with the first query, and then build off that query later on.

## Updating records

Updating records in Ecto requires us to first fetch a record from the database. We then create a changeset from that record and the changes we want to make to that record, and then call the `Ecto.Repo.update` function.

Let's fetch the first person from our database and change their age. First, we'll fetch the person:

```elixir
person = Friends.Person |> Ecto.Query.first |> Friends.Repo.one
```

Next, we'll build a changeset. We need to build a changeset because if we just create a new `Friends.Person` struct with the new age, Ecto wouldn't be able to know that the age has changed without inspecting the database. Let's build that changeset:

```elixir
changeset = Friends.Person.changeset(person, %{age: 29})
```

This changeset will inform the database that we want to update the record to have the `age` set to 29. To tell the database about the change we want to make, we run this command:

```elixir
Friends.Repo.update(changeset)
```

Just like `Friends.Repo.insert`, `Friends.Repo.update` will return a tuple:

```elixir
{:ok,
 %Friends.Person{__meta__: #Ecto.Schema.Metadata<:loaded>, age: 29,
  first_name: "Ryan", id: 1, last_name: "Bigg"}}
```

If the changeset fails for any reason, the result of `Friends.Repo.update` will be `{:error, changeset}`. We can see this in action by passing through a blank `first_name` in our changeset's parameters:

```elixir
changeset = Friends.Person.changeset(person, %{first_name: ""})
#=> {:error,
     #Ecto.Changeset<action: :update, changes: %{first_name: ""},
      errors: [first_name: "can't be blank"], data: #Friends.Person<>,
      valid?: false>}
```

This means that you can also use a `case` statement to do different things depending on the outcome of the `update` function:

```elixir
case Friends.Repo.update(changeset) do
  {:ok, person} ->
    # do something with person
  {:error, changeset} ->
    # do something with changeset
end
```

Similar to `insert!`, there is also `update!` which will raise an exception if the changeset is invalid:

```
changeset = Friends.Person.changeset(person, %{first_name: ""})
Friends.Repo.update! changeset

** (Ecto.InvalidChangesetError) could not perform update because changeset is invalid.

* Changeset changes

%{first_name: ""}

* Changeset params

%{"first_name" => ""}

* Changeset errors

[first_name: {"can't be blank", []}]

    lib/ecto/repo/schema.ex:132: Ecto.Repo.Schema.update!/4
```

## Deleting records

We've now covered creating (`insert`), reading (`get`, `get_by`, `where`) and updating records. The last thing that we'll cover in this guide is how to delete a record using Ecto.

Similar to updating, we must first fetch a record from the database and then call `Friends.Repo.delete` to delete that record:

```elixir
person = Friends.Repo.get(Friends.Person, 1)
Friends.Repo.delete(person)
{:ok,
 %Friends.Person{__meta__: #Ecto.Schema.Metadata<:deleted>, age: 29,
  first_name: "Ryan", id: 2, last_name: "Bigg"}}
```

Similar to `insert` and `update`, `delete` returns a tuple. If the deletion succeeds, then the first element in the tuple will be `:ok`, but if it fails then it will be an `:error`.
