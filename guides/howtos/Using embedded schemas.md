# Using embedded schemas

In this short recipe, we'll learn how to create a basic embedded schema within an existing Ecto schema.

## Scenario

Imagine this scenario: we're building an application that needs to store user profile information. We'd have a `User` schema that looks like this:

```elixir
# User schema
schema "users" do
    field :is_active, :boolean
    # ...
    field :confirmed_at, :naive_datetime

    timestamps()
end
```

The corresponding migration for this schema would be similar to this:

```elixir
create table(:users) do
    add :is_active, :boolean, default: false
    # ...
    add :confirmed_at, :naive_datetime
    timestamps()
end
```

## Write the embedded schema

The first step is to write the schema of the data we're storing. In the case of our profile, we'd like to store the profile and a couple of settings. Let's assume we have a dark mode feature that users can toggle, alongside other information like the user's age. Our embedded schema would look something like this:

```elixir
# UserProfile
embedded_schema do
    field :dark_mode, :boolean
    field :age, :integer
end
```

You can write this embedded schema in a separate module (e.g. `UserProfile` in `user_profile.ex`) or within the `User` schema itself (by replacing the `embedded_schema` macro by either `embeds_one` or `embeds_many`). You can, additionally, write a changeset to validate this data:

```elixir
def changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [:dark_mode, :age])
    |> validate_required([:dark_mode, :age])
end
```

Last but not least, we need to add the embedded schema to the parent, in this case, `User`. Depending on the relation you want, choose between `embeds_one` or `embeds_many`. In this case, our user needs only one profile map, like so:

```elixir
schema "users" do
    field :is_active, :boolean
    # ...
    field :confirmed_at, :naive_datetime

    # Embed the schema to User
    embeds_one :profile, UserProfile

    timestamps()
end
```

## Write the migration

To save this embedded schema to a database, we need to write a corresponding migration. Depending on whether you chose `embeds_one` or `embeds_many`, you must choose the corresponding `map` or `array` data type.

We used `embeds_one`, so the migration should have a type of `map`.

```elixir
alter table("users") do
    add :profile, :map
end
```

## Modify your changesets

Finally, you need to make some adjustments to your `User` changesets.

```elixir
def profile_changeset(user, attrs \\ %{}) do
user
    |> cast(attrs, [:full_name])
    |> cast_attachments(attrs, [:avatar])
    # If your embedded schema's changeset is in another file, use the `with` argument.
    # e.g. cast_embed(:paddle_auth, with: &UserProfile.changeset/2)
    |> cast_embed(:paddle_auth, required: true)
end
```
