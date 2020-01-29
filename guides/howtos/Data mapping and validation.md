# Data mapping and validation

We will take a look at the role schemas play when validating and casting data through changesets. As we will see, sometimes the best solution is not to completely avoid schemas, but break a large schema into smaller ones. Maybe one for reading data, another for writing. Maybe one for your database, another for your forms.

## Schemas are mappers

The `Ecto.Schema` moduledoc says:

> An Ecto schema is used to map *any* data source into an Elixir struct.

We put emphasis on *any* because it is a common misconception to think Ecto schemas map only to your database tables.

For instance, when you write a web application using Phoenix and you use Ecto to receive external changes and apply such changes to your database, we have this mapping:

    Database <-> Ecto schema <-> Forms / API

Although there is a single Ecto schema mapping to both your database and your API, in many situations it is better to break this mapping in two. Let's see some practical examples.

Imagine you are working with a client that wants the "Sign Up" form to contain the fields "First name", "Last name" along side "E-mail" and other information. You know there are a couple problems with this approach.

First of all, not everyone has a first and last name. Although your client is decided on presenting both fields, they are a UI concern, and you don't want the UI to dictate the shape of your data. Furthermore, you know it would be useful to break the "Sign Up" information across two tables, the "accounts" and "profiles" tables.

Given the requirements above, how would we implement the Sign Up feature in the backend?

One approach would be to have two schemas, Account and Profile, with virtual fields such as `first_name` and `last_name`, and [use associations along side nested forms](https://dashbit.co/blog/working-with-ecto-associations-and-embeds) to tie the schemas to your UI. One of such schemas would be:

```elixir
defmodule Profile do
  use Ecto.Schema

  schema "profiles" do
    field :name
    field :first_name, :string, virtual: true
    field :last_name, :string, virtual: true
    ...
  end
end
```

It is not hard to see how we are polluting our Profile schema with UI requirements by adding fields such `first_name` and `last_name`. If the Profile schema is used for both reading and writing data, it may end-up in an awkward place where it is not useful for any, as it contains fields that map just to one or the other operation.

One alternative solution is to break the "Database <-> Ecto schema <-> Forms / API" mapping in two parts. The first will cast and validate the external data with its own structure which you then transform and write to the database. For such, let's define a schema named `Registration` that will take care of casting and validating the form data exclusively, mapping directly to the UI fields:

```elixir
defmodule Registration do
  use Ecto.Schema

  embedded_schema do
    field :first_name
    field :last_name
    field :email
  end
end
```

We used `embedded_schema` because it is not our intent to persist it anywhere. With the schema in hand, we can use Ecto changesets and validations to process the data:

```elixir
fields = [:first_name, :last_name, :email]

changeset =
  %Registration{}
  |> Ecto.Changeset.cast(params["sign_up"], fields)
  |> validate_required(...)
  |> validate_length(...)
```

Now that the registration changes are mapped and validated, we can check if the resulting changeset is valid and act accordingly:

```elixir
if changeset.valid? do
  # Get the modified registration struct from changeset
  registration = Ecto.Changeset.apply_changes(changeset)
  account = Registration.to_account(registration)
  profile = Registration.to_profile(registration)

  MyApp.Repo.transaction fn ->
    MyApp.Repo.insert_all "accounts", [account]
    MyApp.Repo.insert_all "profiles", [profile]
  end

  {:ok, registration}
else
  # Annotate the action so the UI shows errors
  changeset = %{changeset | action: :registration}
  {:error, changeset}
end
```

The `to_account/1` and `to_profile/1` functions in `Registration` would receive the registration struct and split the attributes apart accordingly:

```elixir
def to_account(registration) do
  Map.take(registration, [:email])
end

def to_profile(%{first_name: first, last_name: last}) do
  %{name: "#{first} #{last}"}
end
```

In the example above, by breaking apart the mapping between the database and Elixir and between Elixir and the UI, our code becomes clearer and our data structures simpler.

Note we have used `MyApp.Repo.insert_all/2` to add data to both "accounts" and "profiles" tables directly. We have chosen to bypass schemas altogether. However, there is nothing stopping you from also defining both `Account` and `Profile` schemas and changing `to_account/1` and `to_profile/1` to respectively return `%Account{}` and `%Profile{}` structs. Once structs are returned, they could be inserted through the usual `MyApp.Repo.insert/2` operation. Doing so can be especially useful if there are uniqueness or other constraints that you want to check during insertion.

## Schemaless changesets

Although we chose to define a `Registration` schema to use in the changeset, Ecto also allows developers to use changesets without schemas. We can dynamically define the data and their types. Let's rewrite the registration changeset above to bypass schemas:

```elixir
data = %{}
types = %{name: :string, email: :string}

# The data+types tuple is equivalent to %Registration{}
changeset =
  {data, types}
  |> Ecto.Changeset.cast(params["sign_up"], Map.keys(types))
  |> validate_required(...)
  |> validate_length(...)
```

You can use this technique to validate API endpoints, search forms, and other sources of data. The choice of using schemas depends mostly if you want to use the same mapping in different places or if you desire the compile-time guarantees Elixir structs gives you. Otherwise, you can bypass schemas altogether, be it when using changesets or interacting with the repository.

However, the most important lesson in this guide is not when to use or not to use schemas, but rather understand when a big problem can be broken into smaller problems that can be solved independently leading to an overall cleaner solution. The choice of using schemas or not above didn't affect the solution as much as the choice of breaking the registration problem apart.
