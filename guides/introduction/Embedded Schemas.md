# Embedded Schemas

Embedded schemas allow you to define and validate structured data that is nested within another struct. This data can live exclusively in memory, or can be stored in the database.

Some use cases for embedded schemas include:

- Embedding flexible data that changes often, like a map of user preferences inside a User schema.

- Embedding simple data that you want to track and validate, but where maintaining a separate table and tracking foreign keys and many-to-many relationships is unnecessary, like a list of product images.

- When you want nuanced control over the tracking and validation of a complex struct, like if you wanted a changeset for address validation, but didn't want a separate address table.

- When using document storage databases, and you want to interact with and manipulate embedded documents.

These above use cases have a few themes in common. They all have nested data, and it makes sense for that nested data to be (1) bundled together into a sub-entity, and (2) changeset validations on that sub-entity are desireable.

## Example

Let's explore an example where we have a User and want to store "profile" information about them. The data we want to store here is a loose grouping of UI-dependent information, which is likely to change over time alongside changes in the UI. Also, this data is not necessarily important enough to warrant a new User `field` in the schema, as it is not data that is fundamental to the User. An embedded schema is a good solution for this kind of data.

```elixir
defmodule User do
  use Ecto.Schema

  schema "users" do
    field :full_name, :string
    field :email, :string
    field :avatar_url, :string
    field :confirmed_at, :naive_datetime

    embeds_one :profile do
      field :online, :boolean
      field :dark_mode, :boolean
      field :visibility, Ecto.Enum, values: [:public, :private, :friends_only]
    end

    timestamps()
  end
end
```

### `embeds_one` and `embed_many`

One of the first choices to make is how to represent the embedded data within the struct. Do we want to store an array of structs using `embeds_many`, or just one using `embeds_one`? In our example we are going to use `embeds_one` since users will only ever have one profile associated with them.

```elixir
defmodule User do
  use Ecto.Schema

  schema "users" do
    field :full_name, :string
    field :email, :string
    field :avatar_url, :string
    field :confirmed_at, :naive_datetime

    embeds_one :profile do
      field :online, :boolean
      field :dark_mode, :boolean
      field :visibility, Ecto.Enum, values: [:public, :private, :friends_only]
    end

    timestamps()
  end
end
```

### Extracting embeds

While the above User schema is simple and sufficient, you might find yourself in a situation where you want to work independently with the embedded profile struct. In such scenarios, it is recommended to extract the embedded struct into it's own schema using the `embedded_schema` function.

```elixir
# user/user.ex
defmodule User do
  use Ecto.Schema

  schema "users" do
    field :full_name, :string
    field :email, :string
    field :avatar_url, :string
    field :confirmed_at, :naive_datetime

    embeds_one :profile, UserProfile

    timestamps()
  end
end

# user/user_profile.ex
defmodule UserProfile do
  use Ecto.Schema

  embedded_schema do
      field :online, :boolean
      field :dark_mode, :boolean
      field :visibility, Ecto.Enum, values: [:public, :private, :friends_only]
  end
end
```

### Migrations

In order to save embedded schemas to the database you need to write a migration for the embedded data.

```elixir
alter table("users") do
  add :profile, :map
end
```

Whether you use `embeds_one` or `embeds_many`, it is recommended to use the `:map` data type (although `{:array, :map}` will work with `embeds_many` as well). The reason is that typical relational databases (like Postgres) are likely to represent a `:map` as JSON or JSONB, allowing Ecto adapter libraries more flexibility over how to represent the data, while using `{:array, :map}` requires Ecto adapter libraries to conform more strictly to the databases representation of arrays which could lead to unpredicatable, database-dependent behaviors.

### Changesets

Changeset functionality for embeds will allow you to enforce arbitrary validations on the data. You can define a changeset function for each module. For example, the UserProfile module could require the `online` and `visibility` fields to be present when generating a changeset.

```elixir
defmodule UserProfile do
  # ...

  def changeset(%UserProfile{} = profile, attrs \\ %{}) do
    profile
    |> cast(attrs, [:online, :dark_mode, :visibility])
    |> validate_required([:online, :visibility])
  end
end

profile = %UserProfile{}
UserProfile.changeset(profile, %{online: true, visibility: :public})
```

Meanwhile, the User changeset function can require it's own validations without worrying about the details of the UserProfile changes because it can pass that responsibility to UserProfile via `cast_embed/3`. A validation failure in an embed will cause the parent changeset to be invalid, even if the parent changeset itself had no errors.

```elixir
defmodule User do
  # ...

  def changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [:full_name, :email, :avatar_url])
    |> cast_embed(:profile, required: true)
  end
end

changeset = User.changeset(%User{}, %{profile: %{online: true}})
changeset.valid? # => false; "visibility can't be blank"
changeset = User.changeset(%User{}, %{profile: %{online: true, visibility: :public}})
changeset.valid? # => true
```

In situations where you have kept the embedded schema within the parent module, e.g., you have not extracted a UserProfile, you can still have custom changeset functions for the embedded data within the parent schema.

```elixir
defmodule User do
  use Ecto.Schema

  schema "users" do
    field :full_name, :string
    field :email, :string
    field :avatar_url, :string
    field :confirmed_at, :naive_datetime

    embeds_one :profile, Profile do
      field :online, :boolean
      field :dark_mode, :boolean
      field :visibility, Ecto.Enum, values: [:public, :private, :friends_only]
    end

    timestamps()
  end

  def changeset(%User{} = user, attrs \\ %{}) do
    user
    |> cast(attrs, [:full_name, :email])
    |> cast_embed(:profile, required: true, with: &profile_changeset/2)
  end

  def profile_changeset(profile, attrs \\ %{}) do
    profile
    |> cast(attrs, [:online, :dark_mode, :visibility])
    |> validate_required([:online, :visibility])
  end
end

changeset = User.changeset(%User{}, %{profile: %{online: true, visibility: :public}})
changeset.valid? # => true
```

### Querying embedded data

Once you have written embedded data to the database, you can use it in queries on the parent struct.

<!-- TODO: Actually proves this works with local test data. Otherwise, user JSON query fragments -->
```elixir
from u in User, where: u.profile.dark_mode == true
```
