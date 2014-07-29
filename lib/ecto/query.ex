defmodule Ecto.Query do
  @moduledoc """
  Provides the Query DSL.

  Queries are used to retrieve and manipulate data in a repository
  (see `Ecto.Repo`). Although this module provides a complete API,
  supporting expressions like `where/3`, `select/3` and so forth,
  most of the times developers need to import only the `from/2`
  macro.

      # Imports only from/1 and from/2 from Ecto.Query
      import Ecto.Query, only: [from: 2]

      # Create a query
      query = from w in Weather,
            where: w.prcp > 0,
           select: w.city

      # Send the query to the repository
      Repo.all(query)

  ## Composition

  Ecto queries are composable. For example, the query above can
  actually be defined in two parts:

      # Create a query
      query = from w in Weather, where: w.prcp > 0

      # Extend the query
      query = from w in query, select: w.city

  Keep in mind though the variable names used on the left-hand
  side of `in` are just a convenience, they are not taken into
  account in the query generation.

  Any value can be used on the right-side of `in` as long as it
  implements the `Ecto.Queryable` protocol.

  ## Data security

  External values and elixir expressions can be injected into a query
  expression with `^`. Anything that isn't inside a `^` expression
  is treated as a query expression.

  This allows one to create dynamic queries:

      def with_minimum(age, height_ft) do
          from u in User,
        where: u.age > ^age and u.height > ^(height_ft * 3.28)
      end

  In the example above, we will compare against the `age` and `height`
  given as arguments, appropriately converting the height. Note all
  external values will be quoted to avoid SQL injection attacks in
  the underlying repository.

  Notice the `select` clause is optional, Ecto will automatically infers
  and returns the user record (similar to `select: u`) from the query above.

  ## Type safety

  Ecto queries are also type-safe. For example, the following query:

      from u in User, where: u.age == "zero"

  will return an error with the following message:

      ** (Ecto.Query.TypeCheckError) the following expression does not type check:

          &0.age() == "zero"

      Allowed types for ==/2:

          number == number
          var == var
          nil == _
          _ == nil

      Got: integer == string

  The types above mean:

  * `number == number` - any number (be it float, integer, etc) can be compared
    with any other number;
  * `var == var` - the comparison operator also works if both operands are of
    the same type (i.e. `var` represents a variable type);
  * `nil == _` and `_ == nil` - the comparison operator also type checks if any
    of the operands are nil;

  All operations allowed in a query with their respective type are defined
  in `Ecto.Query.API`.

  ## Query expansion

  In all examples so far, we have used the **keywords query syntax** to create
  a query. Our first example:

      import Ecto.Query

         from w in Weather,
       where: w.prcp > 0,
      select: w.city

  Simply expands to the following **query expressions**:

      from(w in Weather) |> where([w], w.prcp > 0) |> select([w], w.city)

  Which then expands to:

      select(where(from(w in Weather), [w], w.prcp > 0), [w], w.city)

  This module documents each of those macros, providing examples both
  in the keywords query and in the query expression formats.
  """

  defstruct [sources: nil, from: nil, joins: [], wheres: [], select: nil,
             order_bys: [], limit: nil, offset: nil, group_bys: [],
             havings: [], preloads: [], distincts: [], lock: nil]

  defmodule QueryExpr do
    @moduledoc false
    defstruct [:expr, :file, :line]
  end

  defmodule JoinExpr do
    @moduledoc false
    defstruct [:qual, :source, :on, :file, :line, :assoc]
  end

  alias Ecto.Query.FromBuilder
  alias Ecto.Query.WhereBuilder
  alias Ecto.Query.SelectBuilder
  alias Ecto.Query.DistinctBuilder
  alias Ecto.Query.OrderByBuilder
  alias Ecto.Query.LimitOffsetBuilder
  alias Ecto.Query.GroupByBuilder
  alias Ecto.Query.HavingBuilder
  alias Ecto.Query.PreloadBuilder
  alias Ecto.Query.JoinBuilder
  alias Ecto.Query.LockBuilder

  @doc """
  Creates a query.

  It can either be a keyword query or a query expression. If it is a
  keyword query the first argument should be an `in` expression and
  the second argument a keyword query where they keys are expression
  types and the values are expressions.

  If it is a query expression the first argument is the original query
  and the second argument the expression.

  ## Keywords examples

      from(City, select: c)

  ## Expressions examples

      from(City) |> select([c], c)

  ## Examples

      def paginate(query, page, size) do
        from query,
          limit: size,
          offset: (page-1) * size
      end

  The example above does not use `in` because none of `limit` and `offset`
  requires such. However, extending a query with where expression would
  require so:

      def published(query) do
        from p in query, where: p.published_at != nil
      end

  Notice we have created a `p` variable to represent each item in the query.
  In case the given query has more than one `from` expression, each of them
  must be given in the order they were bound:

      def published_multi(query) do
        from [p,o] in query,
        where: p.published_at != nil and o.published_at != nil
      end

  Note the variables `p` and `q` must be named as you find more convenient
  as they have no importance in the query sent to the database.
  """
  defmacro from(expr, kw) do
    unless Keyword.keyword?(kw) do
      raise ArgumentError, reason: "second argument to `from` has to be a keyword list"
    end

    {quoted, binds, count_bind} = FromBuilder.build_with_binds(expr, __CALLER__)
    build_query(kw, __CALLER__, count_bind, quoted, binds)
  end

  @doc """
  A join query expression.

  Receives a model that is to be joined to the query and a condition to
  do the joining on. The join condition can be any expression that evaluates
  to a boolean value. The join is by default an inner join, the qualifier
  can be changed by giving the atoms: `:inner`, `:left`, `:right` or
  `:full`. For a keyword query the `:join` keyword can be changed to:
  `:inner_join`, `:left_join`, `:right_join` or `:full_join`.

  The join condition can be automatically set when doing an association
  join. An association join can be done on any association field
  (`has_many`, `has_one`, `belong_to`).

  ## Keywords examples

         from c in Comment,
        join: p in Post, on: c.post_id == p.id,
      select: {p.title, c.text}

         from p in Post,
        left_join: c in p.comments,
      select: {p, c}

  ## Expressions examples

      from(Comment)
      |> join(:inner, [c], p in Post, c.post_id == p.id)
      |> select([c, p], {p.title, c.text})

      Post
      |> join(:left, [p], c in p.comments)
      |> select([p, c], {p, c})
  """
  defmacro join(query, qual, binding, expr, on \\ nil) do
    JoinBuilder.build_with_binds(query, qual, binding, expr, on, nil, __CALLER__)
    |> elem(0)
  end

  @doc """
  A select query expression.

  Selects which fields will be selected from the model and any transformations
  that should be performed on the fields. Any expression that is accepted in a
  query can be a select field.

  There can only be one select expression in a query, if the select expression
  is omitted, the query will by default select the full model.

  The sub-expressions in the query can be wrapped in lists or tuples as shown in
  the examples. A full model can also be selected.

  The `assoc/2` selector can be used to embed an association on a parent model
  as shown in the examples below. The first argument to `assoc` has to be a
  variable bound in the `from` query expression, the second has to be the field
  of the association and a variable bound in an association join.

  Nested `assoc/2 expressions are also allowed when there are multiple
  association joins in the query.

  ## Keywords examples

      from(c in City, select: c) # selects the entire model
      from(c in City, select: {c.name, c.population})
      from(c in City, select: [c.name, c.county])
      from(c in City, select: {c.name, to_binary(40 + 2), 43})

      from(p in Post, join: c in p.comments, select: assoc(p, comments: c))

      # Fetch all posts, their comments and the posts' and comments' authors
            from p in Post,
      left_join: p_u in p.author,
      left_join: c in p.comments,
      left_join: c_u in c.author,
         select: assoc(p, author: p_u, comments: assoc(c, author: c_u))

  ## Expressions examples

      from(c in City) |> select([c], c)
      from(c in City) |> select([c], {c.name, c.country})

  """
  defmacro select(query, binding, expr) do
    SelectBuilder.build(query, binding, expr, __CALLER__)
  end

  @doc """
  A distinct query expression.

  Only keep one row for each combination of values in the `distinct` query
  expression.

  The row that is being kept depends on the ordering of the rows. To ensure
  results are consistent, if an `order_by` expression is also added to the
  query, its leftmost part must first reference all the fields in the
  `distinct` expression before referencing another field.

  ## Keywords examples

      # Returns the list of different categories in the Post model
      from(p in Post, distinct: p.category)

      # Returns the first (by date) for each different categories of Post
      from(p in Post,
         distinct: p.category,
         order_by: [p.category, p.date])

  ## Expressions examples

      Post
      |> distinct([p], p.category)
      |> order_by([p], [p.category, p.author])

  """
  defmacro distinct(query, binding, expr) do
    DistinctBuilder.build(query, binding, expr, __CALLER__)
  end

  @doc """
  A where query expression.

  `where` expressions are used to filter the result set. If there is more
  than one where expression, they are combined with `and` operator. All
  where expression have to evaluate to a boolean value.

  ## Keywords examples

      from(c in City, where: c.state == "Sweden")

  ## Expressions examples

      from(c in City) |> where([c], c.state == "Sweden")

  """
  defmacro where(query, binding, expr) do
    WhereBuilder.build(query, binding, expr, __CALLER__)
  end

  @doc """
  An order by query expression.

  Orders the fields based on one or more fields. It accepts a single field
  or a list field, the direction can be specified in a keyword list as shown
  in the examples. There can be several order by expressions in a query.

  ## Keywords examples

      from(c in City, order_by: c.name, order_by: c.population)
      from(c in City, order_by: [c.name, c.population])
      from(c in City, order_by: [asc: c.name, desc: c.population])

  ## Expressions examples

      from(c in City) |> order_by([c], asc: c.name, desc: c.population)

  """
  defmacro order_by(query, binding, expr)  do
    OrderByBuilder.build(query, binding, expr, __CALLER__)
  end

  @doc """
  A limit query expression.

  Limits the number of rows selected from the result. Can be any expression but
  have to evaluate to an integer value and it can't include any field.

  If `limit` is given twice, it overrides the previous value.

  ## Keywords examples

      from(u in User, where: u.id == current_user, limit: 1)

  ## Expressions examples

      from(u in User) |> where(u.id == current_user) |> limit(1)

  """
  defmacro limit(query, expr) do
    LimitOffsetBuilder.build(:limit, query, expr, __CALLER__)
  end

  @doc """
  An offset query expression.

  Offsets the number of rows selected from the result. Can be any expression
  but have to evaluate to an integer value and it can't include any field.

  If `offset` is given twice, it overrides the previous value.

  ## Keywords examples

      # Get all posts on page 4
      from(p in Post, limit: 10, offset: 30)

  ## Expressions examples

      from(p in Post) |> limit(10) |> offset(30)

  """
  defmacro offset(query, expr) do
    LimitOffsetBuilder.build(:offset, query, expr, __CALLER__)
  end

  @doc """
  A lock query expression.

  Provides support for row-level pessimistic locking using
  SELECT ... FOR UPDATE or other, database-specific, locking clauses.
  Can be any expression but have to evaluate to a boolean value or a
  string and it can't include any field.

  If `lock` is given twice, it overrides the previous value.

  ## Keywords examples

      from(u in User, where: u.id == current_user, lock: true)
      from(u in User, where: u.id == current_user, lock: \"FOR SHARE NOWAIT\")

  ## Expressions examples

      from(u in User) |> where(u.id == current_user) |> lock(true)
      from(u in User) |> where(u.id == current_user) |> lock(\"FOR SHARE NOWAIT\")

  """
  defmacro lock(query, expr) do
    LockBuilder.build(:lock, query, expr, __CALLER__)
  end

  @doc """
  A group by query expression.

  Groups together rows from the model that have the same values in the given
  fields. Using `group_by` "groups" the query giving it different semantics
  in the `select` expression. If a query is grouped only fields that were
  referenced in the `group_by` can be used in the `select` or if the field
  is given as an argument to an aggregate function.

  ## Keywords examples

      # Returns the number of posts in each category
      from(p in Post,
        group_by: p.category,
        select: {p.category, count(p.id)})

      # Group on all fields on the Post model
      from(p in Post,
        group_by: p,
        select: p)

  ## Expressions examples

      Post |> group_by([p], p.category) |> select([p], count(p.id))

  """
  defmacro group_by(query, binding, expr) do
    GroupByBuilder.build(query, binding, expr, __CALLER__)
  end

  @doc """
  A having query expression.

  Like `where` `having` filters rows from the model, but after the grouping is
  performed giving it the same semantics as `select` for a grouped query
  (see `group_by/3`). `having` groups the query even if the query has no
  `group_by` expression.

  ## Keywords examples

      # Returns the number of posts in each category where the
      # average number of comments is above ten
      from(p in Post,
        group_by: p.category,
        having: avg(p.num_comments) > 10,
        select: {p.category, count(p.id)})

  ## Expressions examples

      Post
      |> group_by([p], p.category)
      |> having([p], avg(p.num_comments) > 10)
      |> select([p], count(p.id))
  """
  defmacro having(query, binding, expr) do
    HavingBuilder.build(query, binding, expr, __CALLER__)
  end

  @doc """
  Mark associations to be pre-loaded.

  Pre-loading allow developers to specify associations that should be pre-
  loaded once the first result set is retrieved. Consider this example:

      Repo.all from p in Post, preload: [:comments]

  The example above will fetch all posts from the database and then do
  a separate query returning all comments associated to the given posts.

  Nested associations can also be preloaded as seen in the examples below.
  One query per association to be preloaded will be issued to the database.

  ## Keywords examples

      # Returns all posts and their associated comments
      from(p in Post,
        preload: [:comments],
        select: p)

      # Returns all posts and their associated comments
      # with the associated author
      from(p in Post,
        preload: [user: [], comments: [:user]],
        select: p)

  ## Expressions examples

      Post |> preload(:comments) |> select([p], p)

      Post |> preload([:user, {:comments, [:user]}]) |> select([p], p)
  """
  defmacro preload(query, expr) do
    PreloadBuilder.build(query, expr, __CALLER__)
  end

  # Builds the quoted code for creating a keyword query

  @binds    [:where, :select, :distinct, :order_by, :group_by, :having]
  @no_binds [:limit, :offset, :preload, :lock]
  @joins    [:join, :inner_join, :left_join, :right_join, :full_join]

  defp build_query([{type, expr}|t], env, count_bind, quoted, binds) when type in @binds do
    # If all bindings are integer indexes keep AST Macro.expand'able to %Query{},
    # otherwise ensure that quoted is evaluated before macro call
    quoted =
      if Enum.all?(binds, fn {_, value} -> is_integer(value) end) do
        quote do
          Ecto.Query.unquote(type)(unquote(quoted), unquote(binds), unquote(expr))
        end
      else
        quote do
          query = unquote(quoted)
          Ecto.Query.unquote(type)(query, unquote(binds), unquote(expr))
        end
      end

    build_query t, env, count_bind, quoted, binds
  end

  defp build_query([{type, expr}|t], env, count_bind, quoted, binds) when type in @no_binds do
    quoted =
      quote do
        Ecto.Query.unquote(type)(unquote(quoted), unquote(expr))
      end

    build_query t, env, count_bind, quoted, binds
  end

  defp build_query([{join, expr}|t], env, count_bind, quoted, binds) when join in @joins do
    qual =
      case join do
        :join       -> :inner
        :inner_join -> :inner
        :left_join  -> :left
        :right_join -> :right
        :full_join  -> :full
      end

    {t, on} = collect_on(t, nil)
    {quoted, binds, count_bind} = JoinBuilder.build_with_binds(quoted, qual, binds, expr, on, count_bind, env)

    build_query t, env, count_bind, quoted, binds
  end

  defp build_query([{:on, _value}|_], _env, _count_bind, _quoted, _binds) do
    raise Ecto.QueryError,
      reason: "`on` keyword must immediately follow a join"
  end

  defp build_query([{key, _value}|_], _env, _count_bind, _quoted, _binds) do
    raise Ecto.QueryError,
      reason: "unsupported #{inspect key} in keyword query expression"
  end

  defp build_query([], _env, _count_bind, quoted, _binds) do
    quoted
  end

  defp collect_on([{:on, expr}|t], nil),
    do: collect_on(t, expr)
  defp collect_on([{:on, expr}|t], acc),
    do: collect_on(t, {:and, [], [acc, expr]})
  defp collect_on(other, acc),
    do: {other, acc}
end
