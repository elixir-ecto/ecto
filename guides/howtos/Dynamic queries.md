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

While many developers prefer the pipe-based syntax, having to repeat the binding `p` made it quite verbose compared to the keyword one. Furthermore, the compile-time aspect of Ecto queries was at odds with building queries dynamically.

Imagine for example a web application that provides search functionality on top of existing posts. The user should be able to specify multiple criteria, such as the author name, the post category, publishing interval, etc. In this case, Ecto's approach would be to process the parameters into regular data structures and then build the query as late as possible.

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

The advantage of interpolating data structures is that we can decouple the processing of parameters from the query generation. Note however not all expressions can be converted to data structures. Since `where` converts a key-value to a `key == value` comparison, order-based comparisons such as `p.published_at > ^minimum_date` still need to be written as part of the query as before.

## The dynamic macro

For cases where we cannot rely on data structures but still desire to build queries dynamically, Ecto includes the `Ecto.Query.dynamic/2` macro.

In order to understand how the `dynamic` macro works let's write a `filter/1` function using both data structures and the `dynamic` macro:

```elixir
def filter(params) do
  Post
  |> order_by(^filter_order_by(params["order_by"]))
  |> where(^filter_where(params))
  |> where(^filter_published_at(params["published_at"]))
end

def filter_order_by("published_at_desc"), do: [desc: :published_at]
def filter_order_by("published_at"),      do: [asc:  :published_at]
def filter_order_by(_),                   do: []

def filter_where(params) do
  for key <- [:author, :category],
      value = params[Atom.to_string(key)],
      do: {key, value}
end

def filter_published_at(date) when is_binary(date),
  do: dynamic([p], p.published_at > ^date)
def filter_published_at(_date),
  do: true
```

The `dynamic` macro allows us to build dynamic expressions that are later interpolated into the query. `dynamic` expressions can also be interpolated into dynamic expressions, allowing developers to build complex expressions dynamically without hassle.

Because we were able to break our problem into smaller functions that receive regular data structures, we can use all the tools available in Elixir to work with data. For handling the `order_by` parameter, it may be best to simply pattern match on the `order_by` parameter. For building the `where` clause, we can traverse the list of known keys and convert them to the format expected by Ecto. For complex conditions, we use the `dynamic` macro.

Testing also becomes simpler as we can test each function in isolation, even when using dynamic queries:

```elixir
test "filter published at based on the given date" do
  assert inspect(filter_published_at("2010-04-17")) ==
         "dynamic([p], p.published_at > ^\"2010-04-17\")"
  assert inspect(filter_published_at(nil)) ==
         "true"
end
```
