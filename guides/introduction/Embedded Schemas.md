# Embedded Schemas

Embedded schemas allow you to define and validate structured data that is nested within another struct. This data can live exclusively in memory, or can be stored in the database with an initial migration.

Some use cases for embedded schemas include:

- Embedding flexible data that changes often, like a map of user preferences inside a User schema.

- Embedding simple data that you want to track and validate, but where maintaining a separate table and tracking foreign keys and many-to-many relationships is unnecessary, like a list of product images.

- When you want nuanced control over the tracking and validation of a complex struct without breaking apart the struct in the data layer, like if you wanted a changeset for address validation, but didn't want a separate address table.

- When using document storage databases, and you want to interact with and manipulate embedded documents.

These above use cases have a few themes in common. They all have nested data, and it makes sense for that nested data to be (1) bundled together into a sub-entity, and (2) changeset validations on that sub-entity are likely desireable.

## Example

Let's look at an example where we have a User and want to store additional information about them. This information is not necessarily important enough to warrant a new User `field` in the schema and database, and also is liable to change often alongside changes in UI and design. An embedded schema is a good solution for this kind of data.

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

One of the first choices to make is how to represent the embedded within the struct. Do we want to store an array of structures (using `embeds_many`) or just one (using `embeds_one`)? In our example we are going to use `embeds_one` since users will only ever have one profile associated with them.

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

Whether you use `embeds_one` or `embeds_many` it is recommended to use the `:map` data type (although `{:array, :map}` will work with `embeds_many`). The reason is that the database is likely to represent a `:map` as JSON or JSONB, allowing Ecto adapters more flexibility over how to represent the data, while using `{:array, :map}` requires Ecto adapter libraries to conform more strictly to the databases representation of arrays which could lead to unpredicatable, database-dependent behaviors.


### Changesets

When it comes to validation, you can define a changeset function for each module. For example, the UserProfile module could require the `online` and `visibility` fields to be present when generating a changeset.

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

Now, when you want to update the UserProfile within a User struct, you will pass the changeset operation down to the UserProfile via the `cast_embed/3` function.

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

  def profile_changeset(%User.Profile{} = profile, attrs \\ %{}) do
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

<!-- TODO: Actually proves this works with local test data -->
```elixir
from u in User, where: u.profile.dark_mode == true
```
