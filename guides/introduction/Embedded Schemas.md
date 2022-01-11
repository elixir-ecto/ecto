# Embedded Schemas

Embedded schemas allow you to define and validate structured data. This data can live in memory, or can be stored in the database. Some use cases for embedded schemas include:

- You are maintaining intermediate-state data, like when UI form fields map onto multiple tables in a database.

- You are working within a persisted parent schema and you want to embed data that is...

  - simple, like a map of user preferences inside a User schema.
  - changes often, like a list of product images with associated structured data inside a Product schema.
  - requires complex tracking and validation, like an Address schema inside a User schema.

- You are using a document storage database and you want to interact with and manipulate embedded documents.

## User Profile Example

Let's explore an example where we have a User and want to store "profile" information about them. The data we want to store is UI-dependent information which is likely to change over time alongside changes in the UI. Also, this data is not necessarily important enough to warrant new User `field`s in the User schema, as it is not data that is fundamental to the User. An embedded schema is a good solution for this kind of data.

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

### Embeds

There are two ways to represent embedded data within a schema, `embeds_many`, which creates a list of embeds, and `embeds_one`, which creates only a single instance of the embed. Your choice here affects the behavior of embed-specific functions like `Ecto.Changeset.put_embed/4` and `Ecto.Changeset.cast_embed/3`, so choose whichever is most appropriate to your use case. In our example we are going to use `embeds_one` since users will only ever have one profile associated with them.

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

### Extracting the embeds

While the above User schema is simple and sufficient, we might want to work independently with the embedded profile struct. For example, if there was a lot of functionality devoted solely to manipulating the profile data, we'd want to consider extracting the embedded schema into its own module.

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

It is important to remember that `embedded_schema` has many use cases independent of `embeds_one` and `embeds_many`. You can think of embedded schemas as persistence agnostic `schema`s. This makes embedded schemas ideal for scenarios where you want to manage structured data without necessarily persisting it. For example, if you want to build a contact form, you still want to parse and validate the data, but the data is likely not persisted anywhere. Instead, it is used to send an email. Embedded schemas would be a good fit for such a use case.

### Migrations

If you wish to save your embedded schema to the database, you need to write a migration to include the embedded data.

```elixir
alter table("users") do
  add :profile, :map
end
```

Whether you use `embeds_one` or `embeds_many`, it is recommended to use the `:map` data type (although `{:array, :map}` will work with `embeds_many` as well). The reason is that typical relational databases are likely to represent a `:map` as JSON (or JSONB in Postgres), allowing Ecto adapter libraries more flexibility over how to efficiently store the data.

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

Meanwhile, the User changeset function can require its own validations without worrying about the details of the UserProfile changes because it can pass that responsibility to UserProfile via `cast_embed/3`. A validation failure in an embed will cause the parent changeset to be invalid, even if the parent changeset itself had no errors.

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

Once you have written embedded data to the database, you can use it in queries on the parent schema.

```elixir
user_changeset = User.changeset(%User{}, %{profile: %{online: true, visibility: :public}})
{:ok, _user} = Repo.insert(user_changeset)

(Ecto.Query.from u in User, select: {u.profile["online"], u.profile["visibility"]}) |> Repo.one
# => {true, "public"}

(Ecto.Query.from u in User, select: u.profile, where: u.profile["visibility"] == ^:public) |> Repo.all
# => [
#  %UserProfile{
#    id: "...",
#    online: true,
#    dark_mode: nil,
#    visibility: :public
#  }
#]
```

In databases where `:map`s are stored as JSONB (like Postgres), Ecto constructs the appropriate jsonpath queries for you. More examples of embedded schema queries are documented in [`json_extract_path/2`](https://hexdocs.pm/ecto/Ecto.Query.API.html#json_extract_path/2).