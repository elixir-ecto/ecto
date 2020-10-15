# Dynamic queries

Ecto was designed from the ground up to have an expressive query API that leverages Elixir syntax to write queries that are pre-compiled for performance and safety. When building queries, we may use the keywords syntax

```elixir
import Ecto.Query

from p in Post,
  where: p.author == "José" and p.category == "Elixir",
  where: p.published_at > ^minimum_date,
  order_by: [desc: p.published_at]
```

or the pipe-based one

```elixir
import Ecto.Query

Post
|> where([p], p.author == "José" and p.category == "Elixir")
|> where([p], p.published_at > ^minimum_date)
|> order_by([p], desc: p.published_at)
```

While many developers prefer the pipe-based syntax, having to repeat the binding `p` made it quite verbose compared to the keyword one.

Another problem with the pre-compiled query syntax is that it has limited options to compose the queries dynamically. Imagine for example a web application that provides search functionality on top of existing posts. The user should be able to specify multiple criteria, such as the author name, the post category, publishing interval, etc.

To solve those problems, Ecto also provides a data-structure centric API to build queries as well as a very powerful mechanism for dynamic queries. Let's take a look.

## Focusing on data structures

Ecto provides a simpler API for both keyword and pipe based queries by making data structures first-class. Let's see an example:

```elixir
from p in Post,
  where: [author: "José", category: "Elixir"],
  where: p.published_at > ^minimum_date,
  order_by: [desc: :published_at]
```

and

```elixir
Post
|> where(author: "José", category: "Elixir")
|> where([p], p.published_at > ^minimum_date)
|> order_by(desc: :published_at)
```

Notice how we were able to ditch the `p` selector in most expressions. In Ecto, all constructs, from `select` and `order_by` to `where` and `group_by`, accept data structures as input. The data structure can be specified at compile-time, as above, and also dynamically at runtime, shown below:

```elixir
where = [author: "José", category: "Elixir"]
order_by = [desc: :published_at]
Post
|> where(^where)
|> where([p], p.published_at > ^minimum_date)
|> order_by(^order_by)
```

While using data-structures already brings a good amount of flexibility to Ecto queries, not all expressions can be converted to data structures. For example, `where` converts a key-value to a `key == value` comparison, and therefore order-based comparisons such as `p.published_at > ^minimum_date` need to be written as before.

## Dynamic fragments

For cases where we cannot rely on data structures but still desire to build queries dynamically, Ecto includes the `Ecto.Query.dynamic/2` macro.

The `dynamic` macro allows us to conditionally build query fragments and interpolate them in the main query. For example, imagine that in the example above you may optionally filter posts by a date of publication. You could of course write it like this:

```elixir
query =
  Post
  |> where(^where)
  |> order_by(^order_by)

query =
  if published_at = params["published_at"] do
    where(query, [p], p.published_at < ^published_at)
  else
    query
  end
```

But with dynamic fragments, you can also write it as:

```elixir
where = [author: "José", category: "Elixir"]
order_by = [desc: :published_at]

filter_published_at =
  if published_at = params["published_at"] do
    dynamic([p], p.published_at < ^published_at)
  else
    true
  end

Post
|> where(^where)
|> where(^filter_published_at)
|> order_by(^order_by)
```

The `dynamic` macro allows us to build dynamic expressions that are later interpolated into the query. `dynamic` expressions can also be interpolated into dynamic expressions, allowing developers to build complex expressions dynamically without hassle.

By using dynamic fragments, we can decouple the processing of parameters from the query generation. Let's see a more complex example.

## Building dynamic queries

Let's go back to the original problem. We want to build a search functionality where the user can configure how to traverse all posts in many different ways. For example, the user may choose how to order the data, filter by author and category, as well as select posts published after a certain date.

To tackle this in Ecto, we can break our problem into a bunch of small functions, that build either data structures or dynamic fragments, and then we interpolate it into the query:

```elixir
def filter(params) do
  Post
  |> order_by(^filter_order_by(params["order_by"]))
  |> where(^filter_where(params))
end

def filter_order_by("published_at_desc"),
  do: [desc: dynamic([p], p.published_at)]

def filter_order_by("published_at"),
  do: [asc: dynamic([p], p.published_at)]

def filter_order_by(_),
  do: []

def filter_where(params) do
  Enum.reduce(params, dynamic(true), fn
    {"author", value}, dynamic ->
      dynamic([p], ^dynamic and p.author == ^value)

    {"category", value}, dynamic ->
      dynamic([p], ^dynamic and p.category == ^value)

    {"published_at", value}, dynamic ->
      dynamic([p], ^dynamic and p.published_at > ^value)

    {_, _}, dynamic ->
      # Not a where parameter
      dynamic
  end)
end
```

Because we were able to break our problem into smaller functions that receive regular data structures, we can use all the tools available in Elixir to work with data. For handling the `order_by` parameter, it may be best to simply pattern match on the `order_by` parameter. For building the `where` clause, we can use `reduce` to start with an empty dynamic (that always returns true) and refine it with new conditions as we traverse the parameters.

Testing also becomes simpler as we can test each function in isolation, even when using dynamic queries:

```elixir
test "filter published at based on the given date" do
  assert dynamic_match?(
           filter_where(%{}),
           "true"
         )

  assert dynamic_match?(
           filter_where(%{"published_at" => "2010-04-17"}),
           "true and q.published_at > ^\"2010-04-17\""
         )
end

defp dynamic_match?(dynamic, string) do
  inspect(dynamic) == "dynamic([q], #{string})"
end
```

In the example above, we created a small helper that allows us to assert on the dynamic contents by matching on the results of `inspect(dynamic)`.

## Dynamic and joins

Even query joins can be tackled dynamically. For example, let's do two modifications to the example above. Let's say we can also sort by author name ("author_name" and "author_name_desc") and at the same time let's say that authors are in a separate table, which means our authors filter in `filter_where` now need to go through the join table.

Our final solution would look like this:

```elixir
def filter(params) do
  Post
  # 1. Add named join binding
  |> join(:inner, [p], assoc(p, :authors), as: :authors)
  |> order_by(^filter_order_by(params["order_by"]))
  |> where(^filter_where(params))
end

# 2. Returned dynamic with join binding
def filter_order_by("published_at_desc"),
  do: [desc: dynamic([p], p.published_at)]

def filter_order_by("published_at"),
  do: dynamic([p], p.published_at)

def filter_order_by("author_name_desc"),
  do: [desc: dynamic([authors: a], a.name)]

def filter_order_by("author_name"),
  do: dynamic([authors: a], a.name)

def filter_order_by(_),
  do: []

# 3. Change the authors clause inside reduce
def filter_where(params) do
  Enum.reduce(params, dynamic(true), fn
    {"author", value}, dynamic ->
      dynamic([authors: a], ^dynamic and a.name == ^value)

    {"category", value}, dynamic ->
      dynamic([p], ^dynamic and p.category == ^value)

    {"published_at", value}, dynamic ->
      dynamic([p], ^dynamic and p.published_at > ^value)

    {_, _}, dynamic ->
      # Not a where parameter
      dynamic
  end)
end
```

Adding more filters in the future is simply a matter of adding more clauses to the `Enum.reduce/3` call in `filter_where`.