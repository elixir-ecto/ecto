# Schemaless queries

Most queries in Ecto are written using schemas. For example, to retrieve all posts in a database, one may write:

```elixir
MyApp.Repo.all(Post)
```

In the construct above, Ecto knows all fields and their types in the schema, rewriting the query above to:

```elixir
query =
  from p in Post,
    select: %Post{title: p.title, body: p.body, ...}

MyApp.Repo.all(query)
```

Although you might use schemas for most of your queries, Ecto also adds the ability to write regular schemaless queries when preferred.

One example is this ability to select all desired fields without duplication:

```elixir
from "posts", select: [:title, :body]
```

When a list of fields is given, Ecto will automatically convert the list of fields to a map or a struct.

Support for passing a list of fields or keyword lists is available to almost all query constructs. For example, we can use an update query to change the title of a given post without a schema:

```elixir
def update_title(post, new_title) do
  query =
    from "posts",
      where: [id: ^post.id],
      update: [set: [title: ^new_title]]

  MyApp.Repo.update_all(query, [])
end
```

The `Ecto.Query.update/3` construct supports four commands:

  * `:set` - sets the given column to the given values
  * `:inc` - increments the given column by the given value
  * `:push` - pushes (appends) the given value to the end of an array column
  * `:pull` - pulls (removes) the given value from an array column

For example, we can increment a column atomically by using the `:inc` command, with or without schemas:

```elixir
def increment_page_views(post) do
  query =
    from "posts",
      where: [id: ^post.id],
      update: [inc: [page_views: 1]]

  MyApp.Repo.update_all(query, [])
end
```

Let's take a look at another example. Imagine you are writing a reporting view, it may be counter-productive to think how your existing application schemas relate to the report being generated. It is often simpler to write a query that returns only the data you need, without trying to fit the data into existing schemas:

```elixir
import Ecto.Query

def running_activities(start_at, end_at) do
  query =
    from u in "users",
      join: a in "activities",
      on: a.user_id == u.id,
      where:
        a.start_at > type(^start_at, :naive_datetime) and
          a.end_at < type(^end_at, :naive_datetime),
      group_by: a.user_id,
      select: %{
        user_id: a.user_id,
        interval: a.end_at - a.start_at,
        count: count(u.id)
      }

  MyApp.Repo.all(query)
end
```

The function above does not rely on schemas. It returns only the data that matters for building the report. Notice how we use the `type/2` function to specify what is the expected type of the argument we are interpolating, benefiting from the same type casting guarantees a schema would give.

By allowing regular data structures to be given to most query operations, Ecto makes queries with and without schemas more accessible. Not only that, it also enables developers to write dynamic queries, where fields, filters, ordering cannot be specified upfront.

## insert_all, update_all and delete_all

Ecto allows all database operations to be expressed without a schema. One of the functions provided is `c:Ecto.Repo.insert_all/3`. With `insert_all`, developers can insert multiple entries at once into a repository using the source and a list of fields and values to be passed directly to the adapter:

```elixir
MyApp.Repo.insert_all(
  "posts",
  [
    [title: "hello", body: "world"],
    [title: "another", body: "post"]
  ]
)
```

Updates and deletes can also be done without schemas via `c:Ecto.Repo.update_all/3` and `c:Ecto.Repo.delete_all/2` respectively:

```elixir
# Use the ID to trigger updates
post = from p in "posts", where: [id: ^id]

# Update the title for all matching posts
{1, _} =
  MyApp.Repo.update_all post, set: [title: "new title"]

# Delete all matching posts
{1, _} =
  MyApp.Repo.delete_all post
```

It is not hard to see how these operations directly map to their SQL variants, keeping the database at your fingertips without the need to intermediate all operations through schemas.
