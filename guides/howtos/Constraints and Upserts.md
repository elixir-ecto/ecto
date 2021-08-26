# Constraints and Upserts

In this guide we will learn how to use constraints and upserts. To showcase those features, we will work on a practical scenario: which is by studying a many to many relationship between posts and tags.

## put_assoc vs cast_assoc

Imagine we are building an application that has blog posts and such posts may have many tags. Not only that, a given tag may also belong to many posts. This is a classic scenario where we would use `many_to_many` associations. Our migrations would look like:

```elixir
create table(:posts) do
  add :title, :string
  add :body, :text
  timestamps()
end

create table(:tags) do
  add :name, :string
  timestamps()
end

create unique_index(:tags, [:name])

create table(:posts_tags, primary_key: false) do
  add :post_id, references(:posts)
  add :tag_id, references(:tags)
end
```

Note we added a unique index to the tag name because we don't want to have duplicated tags in our database. It is important to add an index at the database level instead of using a validation since there is always a chance two tags with the same name would be validated and inserted simultaneously, passing the validation and leading to duplicated entries.

Now let's also imagine we want the user to input such tags as a list of words split by comma, such as: "elixir, erlang, ecto". Once this data is received in the server, we will break it apart into multiple tags and associate them to the post, creating any tag that does not yet exist in the database.

While the constraints above sound reasonable, that's exactly what put us in trouble with `cast_assoc/3`. The `cast_assoc/3` changeset function was designed to receive external parameters and compare them with the associated data in our structs. To do so correctly, Ecto requires tags to be sent as a list of maps. We can see an example of this in [Polymorphic associations with many to many](Polymorphic associations with many to many.md). However, here we expect tags to be sent in a string separated by comma.

Furthermore, `cast_assoc/3` relies on the primary key field for each tag sent in order to decide if it should be inserted, updated or deleted. Again, because the user is simply passing a string, we don't have the ID information at hand.

When we can't cope with `cast_assoc/3`, it is time to use `put_assoc/4`. In `put_assoc/4`, we give Ecto structs or changesets instead of parameters, giving us the ability to manipulate the data as we want. Let's define the schema and the changeset function for a post which may receive tags as a string:

```elixir
defmodule MyApp.Post do
  use Ecto.Schema

  schema "posts" do
    field :title
    field :body

    many_to_many :tags, MyApp.Tag,
      join_through: "posts_tags",
      on_replace: :delete

    timestamps()
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> Ecto.Changeset.cast(params, [:title, :body])
    |> Ecto.Changeset.put_assoc(:tags, parse_tags(params))
  end

  defp parse_tags(params)  do
    (params["tags"] || "")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(& &1 == "")
    |> Enum.map(&get_or_insert_tag/1)
  end

  defp get_or_insert_tag(name) do
    Repo.get_by(MyApp.Tag, name: name) ||
      Repo.insert!(%Tag{name: name})
  end
end
```

In the changeset function above, we moved all the handling of tags to a separate function, called `parse_tags/1`, which checks for the parameter, breaks each tag apart via `String.split/2`, then removes any left over whitespace with `String.trim/1`, rejects any empty string and finally checks if the tag exists in the database or not, creating one in case none exists.

The `parse_tags/1` function is going to return a list of `MyApp.Tag` structs which are then passed to `put_assoc/4`. By calling `put_assoc/4`, we are telling Ecto those should be the tags associated to the post from now on. In case a previous tag was associated to the post and not given in `put_assoc/4`, Ecto will invoke the behaviour defined in the `:on_replace` option, which we have set to `:delete`. The `:delete` behaviour will remove the association between the post and the removed tag from the database.

And that's all we need to use `many_to_many` associations with `put_assoc/4`. `put_assoc/4` is very useful when we want to have more explicit control over our associations and it also works with `has_many`, `belongs_to` and all others association types.

However, our code is not yet ready for production. Let's see why.

## Constraints and race conditions

Remember we added a unique index to the tag `:name` column when creating the tags table. We did so to protect us from having duplicate tags in the database.

By adding the unique index and then using `get_by`  with a `insert!` to get or insert a tag, we introduced a potential error in our application. If two posts are submitted at the same time with a similar tag, there is a chance we will check if the tag exists at the same time, leading both submissions to believe there is no such tag in the database. When that happens, only one of the submissions will succeed while the other one will fail. That's a race condition: your code will error from time to time, only when certain conditions are met. And those conditions are time sensitive.

Luckily Ecto gives us a mechanism to handle constraint errors from the database.

## Checking for constraint errors

Since our `get_or_insert_tag(name)` function fails when a tag already exists in the database, we need to handle such scenarios accordingly. Let's rewrite it taking race conditions into account:

```elixir
defp get_or_insert_tag(name) do
  %Tag{}
  |> Ecto.Changeset.change(name: name)
  |> Ecto.Changeset.unique_constraint(:name)
  |> Repo.insert()
  |> case do
    {:ok, tag} -> tag
    {:error, _} -> Repo.get_by!(MyApp.Tag, name: name)
  end
end
```

Instead of inserting the tag directly, we now build a changeset, which allows us to use the `unique_constraint` annotation. Now if the `Repo.insert` operation fails because the unique index for `:name` is violated, Ecto won't raise, but return an `{:error, changeset}` tuple. Therefore, if `Repo.insert` succeeds, it is because the tag was saved, otherwise the tag already exists, which we then fetch with `Repo.get_by!`.

While the mechanism above fixes the race condition, it is a quite expensive one: we need to perform two queries for every tag that already exists in the database: the (failed) insert and then the repository lookup. Given that's the most common scenario, we may want to rewrite it to the following:

```elixir
defp get_or_insert_tag(name) do
  Repo.get_by(MyApp.Tag, name: name) ||
    maybe_insert_tag(name)
end

defp maybe_insert_tag(name) do
  %Tag{}
  |> Ecto.Changeset.change(name: name)
  |> Ecto.Changeset.unique_constraint(:name)
  |> Repo.insert
  |> case do
    {:ok, tag} -> tag
    {:error, _} -> Repo.get_by!(MyApp.Tag, name: name)
  end
end
```

The above performs 1 query for every tag that already exists, 2 queries for every new tag and possibly 3 queries in the case of race conditions. While the above would perform slightly better on average, Ecto has a better option in stock.

## Upserts

Ecto supports the so-called "upsert" command which is an abbreviation for "update or insert". The idea is that we try to insert a record and in case it conflicts with an existing entry, for example due to a unique index, we can choose how we want the database to act by either raising an error (the default behaviour), ignoring the insert (no error) or by updating the conflicting database entries.

"upsert" in Ecto is done with the `:on_conflict` option. Let's rewrite `get_or_insert_tag(name)` once more but this time using the `:on_conflict` option. Remember that "upsert" is a new feature in PostgreSQL 9.5, so make sure you are up to date.

Your first try in using `:on_conflict` may be by setting it to `:nothing`, as below:

```elixir
defp get_or_insert_tag(name) do
  Repo.insert!(
    %MyApp.Tag{name: name},
    on_conflict: :nothing
  )
end
```

While the above won't raise an error in case of conflicts, it also won't update the struct given, so it will return a tag without ID. One solution is to force an update to happen in case of conflicts, even if the update is about setting the tag name to its current name. In such cases, PostgreSQL also requires the `:conflict_target` option to be given, which is the column (or a list of columns) we are expecting the conflict to happen:

```elixir
defp get_or_insert_tag(name) do
  Repo.insert!(
    %MyApp.Tag{name: name},
    on_conflict: [set: [name: name]],
    conflict_target: :name
  )
end
```

And that's it! We try to insert a tag with the given name and if such tag already exists, we tell Ecto to update its name to the current value, updating the tag and fetching its id. While the above is certainly a step up from all solutions so far, it still performs one query per tag. If 10 tags are sent, we will perform 10 queries. Can we further improve this?

## Upserts and insert_all

Ecto accepts the `:on_conflict` option not only in `c:Ecto.Repo.insert/2` but also in the `c:Ecto.Repo.insert_all/3` function. This means we can build one query that attempts to insert all missing tags and then another query that fetches all of them at once. Let's see how our `Post` schema will look like after those changes:

```elixir
defmodule MyApp.Post do
  use Ecto.Schema

  # We need to import Ecto.Query
  import Ecto.Query

  # Schema is the same
  schema "posts" do
    add :title
    add :body

    many_to_many :tags, MyApp.Tag,
      join_through: "posts_tags",
      on_replace: :delete

    timestamps()
  end

  # Changeset is the same
  def changeset(struct, params \\ %{}) do
    struct
    |> Ecto.Changeset.cast(params, [:title, :body])
    |> Ecto.Changeset.put_assoc(:tags, parse_tags(params))
  end

  # Parse tags has slightly changed
  defp parse_tags(params)  do
    (params["tags"] || "")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(& &1 == "")
    |> insert_and_get_all()
  end

  defp insert_and_get_all([]) do
    []
  end
  defp insert_and_get_all(names) do
    timestamp =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.truncate(:second)

    placeholders = %{timestamp: timestamp}

    maps =
      Enum.map(names, &%{
        name: &1,
        inserted_at: {:placeholder, :timestamp},
        updated_at: {:placeholder, :timestamp}
      })

    Repo.insert_all(
      MyApp.Tag,
      maps,
      placeholders: placeholders,
      on_conflict: :nothing
    )

    Repo.all(from t in MyApp.Tag, where: t.name in ^names)
  end
end
```

Instead of getting and inserting each tag individually, the code above works on all tags at once, first by building a list of maps which is given to `insert_all`. Then we look up all tags with the given names. Regardless of how many tags are sent, we will perform only 2 queries - unless no tag is sent, in which we return an empty list back promptly. This solution is only possible thanks to the `:on_conflict` option, which guarantees `insert_all` won't fail in case a unique index is violated, such as from duplicate tag names. Remember, `insert_all` won't autogenerate values like timestamps. That's why we define a timestamp placeholder and reuse it across `inserted_at` and `updated_at` fields.

Finally, keep in mind that we haven't used transactions in any of the examples so far. That decision was deliberate as we relied on the fact that getting or inserting tags is an idempotent operation, i.e. we can repeat it many times for a given input and it will always give us the same result back. Therefore, even if we fail to introduce the post to the database due to a validation error, the user will be free to resubmit the form and we will just attempt to get or insert the same tags once again. The downside of this approach is that tags will be created even if creating the post fails, which means some tags may not have posts associated to them. In case that's not desired, the whole operation could be wrapped in a transaction or modeled with `Ecto.Multi`.
