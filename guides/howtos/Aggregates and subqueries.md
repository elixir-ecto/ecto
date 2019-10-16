# Aggregates and subqueries

Now it's time to discuss aggregates and subqueries. As we will learn, one builds directly on the other.

## Aggregates

Ecto includes a convenience function in repositories to calculate aggregates.

For example, if we assume every post has an integer column named visits, we can find the average number of visits across all posts with:

```elixir
MyApp.Repo.aggregate(MyApp.Post, :avg, :visits)
#=> #Decimal<1743>
```

Behind the scenes, the query above translates to:

```elixir
MyApp.Repo.one(from p in MyApp.Post, select: avg(p.visits))
```

The `c:Ecto.Repo.aggregate/4` function supports any of the aggregate operations listed in the `Ecto.Query.API` module.

At first, it looks like the implementation of `aggregate/4` is quite straight-forward. You could even start to wonder why it was added to Ecto in the first place. However, complexities start to arise on queries that rely on `limit`, `offset` or `distinct` clauses.

Imagine that instead of calculating the average of all posts, you want the average of only the top 10. Your first try may be:

```elixir
MyApp.Repo.one(
  from p in MyApp.Post,
    order_by: [desc: :visits],
    limit: 10,
    select: avg(p.visits)
)
#=> #Decimal<1743>
```

Oops. The query above returned the same value as the queries before. The option `limit: 10` has no effect here since it is limiting the aggregated result and queries with aggregates return only a single row anyway. In order to retrieve the correct result, we would need to first find the top 10 posts and only then aggregate. That's exactly what `aggregate/4` does:

```elixir
query =
  from MyApp.Post,
    order_by: [desc: :visits],
    limit: 10

MyApp.Repo.aggregate(query, :avg, :visits)
#=> #Decimal<4682>
```

When `limit`, `offset` or `distinct` is specified in the query, `aggregate/4` automatically wraps the given query in a subquery. Therefore the query executed by `aggregate/4` above is rather equivalent to:

```elixir
inner_query =
  from MyApp.Post,
    order_by: [desc: :visits],
    limit: 10

query =
  from q in subquery(inner_query),
  select: avg(q.visits)

MyApp.Repo.one(query)
```

Let's take a closer look at subqueries.

## Subqueries

In the previous section we have already learned some queries that would be hard to express without support for subqueries. That's one of many examples that caused subqueries to be added to Ecto.

Subqueries in Ecto are created by calling `Ecto.Query.subquery/1`. This function receives any data structure that can be converted to a query, via the `Ecto.Queryable` protocol, and returns a subquery construct (which is also queryable).

In Ecto, it is allowed for a subquery to select a whole table (`p`) or a field (`p.field`). All fields selected in a subquery can be accessed from the parent query. Let's revisit the aggregate query we saw in the previous section:

```elixir
inner_query =
  from MyApp.Post,
    order_by: [desc: :visits],
    limit: 10

query =
  from q in subquery(inner_query),
    select: avg(q.visits)

MyApp.Repo.one(query)
```

Because the query does not specify a `:select` clause, it will return `select: p` where `p` is controlled by `MyApp.Post` schema. Since the query will return all fields in `MyApp.Post`, when we convert it to a subquery, all of the fields from `MyApp.Post` will be available on the parent query, such as `q.visits`. In fact, Ecto will keep the schema properties across queries. For example, if you write `q.field_that_does_not_exist`, your Ecto query won't compile.

Ecto also allows an Elixir map to be returned from a subquery, making the map keys directly available to the parent query.

Let's see one last example. Imagine you manage a library (as in an actual library in the real world) and there is a table that logs every time the library lends a book. The "lendings" table uses an auto-incrementing primary key and can be backed by the following schema:

```elixir
defmodule Library.Lending do
  use Ecto.Schema

  schema "lendings" do
    belongs_to :book, MyApp.Book       # defines book_id
    belongs_to :visitor, MyApp.Visitor # defines visitor_id
  end
end
```

Now consider we want to retrieve the name of every book alongside the name of the last person the library has lent it to. To do so, we need to find the last lending ID of every book, and then join on the book and visitor tables. With subqueries, that's straight-forward:

```elixir
last_lendings =
  from l in MyApp.Lending,
    group_by: l.book_id,
    select: %{
      book_id: l.book_id,
      last_lending_id: max(l.id)
    }

from l in Lending,
  join: last in subquery(last_lendings),
  on: last.last_lending_id == l.id,
  join: b in assoc(l, :book),
  join: v in assoc(l, :visitor),
  select: {b.name, v.name}
```
