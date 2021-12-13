# Embedded Schemas

Embedded schemas are a feature in Ecto that allows you to define and validate structured data. This data can reside in-memory through structs or, with a migration, be stored in a database field. Embedded schemas work with maps and arrays.

They're great for:

- Storing additional data about an entity without modifying your schema.
- Storing additional data about an entity without tedious foreign key/many-to-many relationships
- Validating arbitrary data structures

Example use cases:

- User profiles: storing information like profile pictures, settings
- Shop products: storing additional product images

While embedded schemas require an initial migration to create the field, any subsequent modifications to the data structure don't.

This feature is great for situations where you'd like to store data associated to a specific entity, but a relation or new table would be overkill. You can even write changesets to perform validations on this data!

## Example

An example of embedded schemas is to store additional information about the current user. The finished example for this guide's embedded schema will look like this:

```elixir
defmodule User do
  use Ecto.Schema

  schema "users" do
    field :is_active, :boolean
    field :email, :string
    field :confirmed_at, :naive_datetime

    embeds_one "profile" do
      field :age, :integer
      field :favorite_color, Ecto.Enum, values: [:red, :green, :blue, :pink, :black, :orange]
      field :avatar_url, :string
    end

    timestamps()
  end
end
```

Let's kick things off with a tutorial to explain how to recreate this use case: building a solution for user profiles in an example app.

### Writing the schema

The first step is to write the structure of the data we're storing. In the case of our profile, we'd like to store the user's age, favorite color, and a profile picture.

To begin writing this embedded schema, we must first think about what structure we want. Do we want to store an array of structures (using `embeds_many`) or just one (using `embeds_one`)?

In this case, every user should have only one profile associated to them, so we'll begin by writing like any other Ecto schema:

```elixir
defmodule User do
  use Ecto.Schema

  schema "users" do
    field :is_active, :boolean
    field :email, :string
    field :confirmed_at, :naive_datetime

    embeds_one :profile do
      field :age, :integer
      field :favorite_color, Ecto.Enum, values: [:red, :green, :blue, :pink, :black, :orange]
      field :avatar_url, :string
    end

    timestamps()
  end
end
```

We can, however, clean this up a little. You can separate the profile to a distinct module and keep the `User` module tidy:

```elixir
# user/user.ex
defmodule User do
  use Ecto.Schema

  schema "users" do
    field :is_active, :boolean
    field :email, :string
    field :confirmed_at, :naive_datetime

    embeds_one :profile, UserProfile
    timestamps()
  end
end

# user/user_profile.ex
defmodule UserProfile do
  use Ecto.Schema

  embedded_schema "profile" do
    field :age, :integer
    field :favorite_color, Ecto.Enum, values: [:red, :green, :blue, :pink, :black, :orange]
    field :avatar_url, :string
  end
end
```

Ta-da! Neat. Note we replaced the `embeds_one` macro by `embedded_schema`: `embeds_one` and `embeds_many` function like fields, similar to relations like `has_many`.

### Writing the migration

To save this embedded schema to a database, we need to write a corresponding migration. Depending on whether you chose `embeds_one` or `embeds_many`, you must choose the corresponding `map` or `array` data type.

We used `embeds_one`, so the migration should have a type of `map`.

```elixir
alter table("users") do
  add :profile, :map
end
```

### Using changesets

When it comes to validation, you can define a changeset function for each module. For example, the module may say that both `age` and `favorite_color` fields are required:

```elixir
defmodule UserProfile do
  # ...

  def changeset(profile, attrs \\ %{}) do
    profile
    |> cast(attrs, [:age, :favorite_color, :avatar_url])
    |> validate_required([:age, :favorite_color])
  end
end
```

On the user side, you also define a `changeset/2` function, and then you use `cast_embed/3` to invoke the `UserProfile` changeset:

```elixir
defmodule User do
  use Ecto.Schema

  # ...

  def changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [:full_name, :email])
    # By default it calls UserProfile.changeset/2, pass the :with option to change it
    |> cast_embed(:user_profile, required: true)
  end
end
```
