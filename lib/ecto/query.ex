defmodule Ecto.Query do
  @moduledoc """
  Provides the Query DSL.

  Queries are used to retrieve and manipualte data in a repository
  (see `Ecto.Repo`). Although this module provides a complete API,
  supporting expressions like `where/3`, `select/3` and so forth,
  most of the times developers need to import only the `from/1` and
  `from/2` macros. That is exactly the API that `use Ecto.Query`
  provides out of the box:

      # Imports only from/1 and from/2 from Ecto.Query
      use Ecto.Query

      # Create a query
      query = from w in Weather,
            where: w.prcp > 0,
           select: w.city

      # econd the query to the repository
      Repo.all(query)

  ## Composition

  Ecto queries are composable. For example, the query above can
  actually be defined in two parts:

      # Create a query
      query = from w in Weather, where: w.prcp > 0,

      # Extend the query
      query = from w in query, select: w.city

  Keep in mind though the variable names used on the left-hand
  side of `in` are just a convenience, they are not taken into
  account in the query generation.

  Any value can used on the right-side of `in` as long as it
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
  given as arguments, appropriately convering the height. Note all
  external values will be quoted to avoid SQL injection attacks in
  the underlying repository.

  Notice the `select` clause is optional, Ecto will automatically infers
  and returns the user record (similar to `select: u`) from the query above.

  ## Type safety

  Ecto queries are also type-safe. For example, the following query:

      from u in User, where: u.age == "zero"

  will error with the following message:

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

  defrecord Query, sources: nil, from: nil, joins: [], wheres: [], select: nil,
                   order_bys: [], limit: nil, offset: nil, group_bys: [],
                   havings: [], preloads: []

  defrecord QueryExpr, [:expr, :file, :line]
  defrecord AssocJoinExpr, [:qual, :expr, :file, :line]
  defrecord JoinExpr, [:qual, :source, :on, :file, :line]

  @type t :: Query.t

  alias Ecto.Query.BuilderUtil
  alias Ecto.Query.FromBuilder
  alias Ecto.Query.WhereBuilder
  alias Ecto.Query.SelectBuilder
  alias Ecto.Query.OrderByBuilder
  alias Ecto.Query.LimitOffsetBuilder
  alias Ecto.Query.GroupByBuilder
  alias Ecto.Query.HavingBuilder
  alias Ecto.Query.PreloadBuilder
  alias Ecto.Query.JoinBuilder
  alias Ecto.Query.Util

  @doc false
  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__), only: [from: 1, from: 2]
    end
  end

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
  as they have no important in the query sent to the database.
  """
  defmacro from(expr, kw) do
    unless Keyword.keyword?(kw) do
      raise ArgumentError, reason: "second argument to `from` has to be a keyword list"
    end

    { binds, _ } = FromBuilder.escape(expr)
    quoted = FromBuilder.build(expr, __CALLER__)
    build_query(quoted, binds, kw)
  end

  @doc """
  Creates a query with a from query expression.

  ## Examples

      from(c in City)

  """
  defmacro from(kw) when is_list(kw) do
    quote do
      Ecto.Query.from(Ecto.Query.Query[], unquote(kw))
    end
  end

  defmacro from(expr) do
    FromBuilder.build(expr, __CALLER__)
  end

  @doc """
  A join query expression.

  Receives an entity that is to be joined to the query and a condition to
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
      select: { p.title, c.text }

         from p in Post,
        left_join: c in p.comments,
      select: { p, c }

  ## Expressions examples

      from(Comment)
        |> join(:inner, [c], p in Post, c.post_id == p.id)
        |> select([c, p], { p.title, c.text })

      from(Post)
        |> join(:left, [p], c in p.comments)
        |> select([p, c], { p, c })
  """
  defmacro join(query, qual, binding, expr, on // nil) do
    binding = BuilderUtil.escape_binding(binding)
    { expr_bindings, join_expr } = JoinBuilder.escape(expr, binding)

    is_assoc = Ecto.Associations.assoc_join?(join_expr)
    unless is_assoc == nil?(on) do
      raise Ecto.QueryError, reason: "`join` expression requires explicit `on` " <>
        "expression unless association join expression"
    end
    if (bind = Enum.first(expr_bindings)) && bind in binding do
      raise Ecto.QueryError, reason: "variable `#{bind}` is already defined in query"
    end

    on_expr = if on do
      binds = binding ++ expr_bindings
      WhereBuilder.escape(on, binds, bind)
    end

    quote do
      query = unquote(query)
      qual = unquote(qual)
      join_expr = unquote(join_expr)

      JoinBuilder.validate_qual(qual)
      var!(count_binds, Ecto.Query) = Util.count_binds(query)

      if unquote(is_assoc) do
        join = AssocJoinExpr[qual: qual, expr: join_expr, file: __ENV__.file, line: __ENV__.line]
      else
        on = QueryExpr[expr: unquote(on_expr), file: __ENV__.file, line: __ENV__.line]
        join = JoinExpr[qual: qual, source: join_expr, on: on, file: __ENV__.file, line: __ENV__.line]
      end
      Util.merge(query, :join, join)
    end
  end

  @doc """
  A select query expression.

  Selects which fields will be selected from the entity and any transformations
  that should be performed on the fields. Any expression that is accepted in a
  query can be a select field.

  There can only be one select expression in a query, if the select expression is
  omitted, the query will by default select the full entity (only works when there
  is a single `from` expression and no `group_by`).

  The sub-expressions in the query can be wrapped in lists or tuples as shown in
  the examples. A full entity can also be selected if the entity variable is the
  only thing in the expression.

  The `assoc/2` selector can be used to embed an association on a parent entity
  as shown in the examples below. The first argument to `assoc` has to be a
  variable bound in the `from` query expression, the second has to be a variable
  bound in an association join on the `from` variable.

  ## Keywords examples

      from(c in City, select: c) # selects the entire entity
      from(c in City, select: { c.name, c.population })
      from(c in City, select: [c.name, c.county])
      from(c in City, select: { c.name, to_binary(40 + 2), 43 })

      from(p in Post, join: c in p.comments, select: assoc(p, c))

  ## Expressions examples

      from(c in City) |> select([c], c)
      from(c in City) |> select([c], { c.name, c.country })

  """
  defmacro select(query, binding, expr) do
    SelectBuilder.build(query, binding, expr, __CALLER__)
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
    binding = BuilderUtil.escape_binding(binding)
    quote do
      query = unquote(query)
      where_expr = unquote(WhereBuilder.escape(expr, binding))
      where = QueryExpr[expr: where_expr, file: __ENV__.file, line: __ENV__.line]
      Util.merge(query, :where, where)
    end
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
    binding = BuilderUtil.escape_binding(binding)
    quote do
      query = unquote(query)
      expr = unquote(OrderByBuilder.escape(expr, binding))
      order_by = QueryExpr[expr: expr, file: __ENV__.file, line: __ENV__.line]
      Util.merge(query, :order_by, order_by)
    end
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
  but have to evaluate to an integer value and tt can't include any field.

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
  A group by query expression.

  Groups together rows from the entity that have the same values in the given
  fields. Using `group_by` "groups" the query giving it different semantics
  in the `select` expression. If a query is grouped only fields that were
  referenced in the `group_by` can be used in the `select` or if the field
  is given as an argument to an aggregate function.

  ## Keywords examples

      # Returns the number of posts in each category
      from(p in Post,
        group_by: p.category,
        select: { p.category, count(p.id) })

      # Group on all fields on the Post entity
      from(p in Post,
        group_by: p,
        select: p)

  ## Expressions examples

      from(Post) |> group_by([p], p.category) |> select([p], count(p.id))

  """
  defmacro group_by(query, binding, expr) do
    binding = BuilderUtil.escape_binding(binding)
    quote do
      query = unquote(query)
      expr = unquote(GroupByBuilder.escape(expr, binding))
      group_by = QueryExpr[expr: expr, file: __ENV__.file, line: __ENV__.line]
      Util.merge(query, :group_by, group_by)
    end
  end

  @doc """
  A having query expression.

  Like `where` `having` filters rows from the entity, but after the grouping is
  performed giving it the same semantics as `select` for a grouped query
  (see `group_by/3`). `having` groups the query even if the query has no
  `group_by` expression.

  ## Keywords examples

      # Returns the number of posts in each category where the
      # average number of comments is above ten
      from(p in Post,
        group_by: p.category,
        having: avg(p.num_comments) > 10,
        select: { p.category, count(p.id) })

  ## Expressions examples

      from(Post)
        |> group_by([p], p.category)
        |> having([p], avg(p.num_comments) > 10)
        |> select([p], count(p.id))
  """
  defmacro having(query, binding, expr) do
    binding = BuilderUtil.escape_binding(binding)
    quote do
      query = unquote(query)
      having_expr = unquote(HavingBuilder.escape(expr, binding))
      having = QueryExpr[expr: having_expr, file: __ENV__.file, line: __ENV__.line]
      Util.merge(query, :having, having)
    end
  end

  @doc """
  Mark associations to be pre-loaded.

  Pre-loading allow developers to specify associations that should be pre-
  loaded once the first result set is retrieved. Consider this example:

      Repo.all from p in Post, preload: [:comments]

  The example above will fetch all posts from the database and then do
  a separate query returning all comments associated to the given posts.

  ## Keywords examples

      # Returns all posts and their associated comments
      from(p in Post,
        preload: [:comments],
        select: p)

  ## Expressions examples

      from(Post) |> preload(:comments) |> select([p], p)
  """
  defmacro preload(query, expr) do
    expr = List.wrap(expr)
    PreloadBuilder.validate(expr)
    quote do
      query = unquote(query)
      preload_expr = unquote(expr)
      preload = QueryExpr[expr: preload_expr, file: __ENV__.file, line: __ENV__.line]
      Util.merge(query, :preload, preload)
    end
  end

  defrecord KwState, [:quoted, :binds]

  # Builds the quoted code for creating a keyword query
  defp build_query(quoted, binds, kw) do
    state = KwState[quoted: quoted, binds: binds]
    Enum.reduce(kw, state, &build_query_type(&1, &2)).quoted
  end

  defp build_query_type({ :from, expr }, KwState[] = state) do
    { binds, expr } = FromBuilder.escape(expr)

    Enum.each binds, fn bind ->
      if bind != :_ and bind in state.binds do
        raise Ecto.QueryError, reason: "variable `#{bind}` is already defined in query"
      end
    end

    quoted = quote do: Util.merge(unquote(state.quoted), :from, unquote(expr))
    state.quoted(quoted).binds(state.binds ++ binds)
  end

  @joins [:join, :inner_join, :left_join, :right_join, :full_join]

  defp build_query_type({ join, expr }, state) when join in @joins do
    case join do
      :join       -> build_join(:inner, expr, state)
      :inner_join -> build_join(:inner, expr, state)
      :left_join  -> build_join(:left, expr, state)
      :right_join -> build_join(:right, expr, state)
      :full_join  -> build_join(:full, expr, state)
    end
  end

  defp build_query_type({ :on, expr }, KwState[] = state) do
    quoted = quote do
      expr = unquote(WhereBuilder.escape(expr, state.binds))
      on = QueryExpr[expr: expr, file: __ENV__.file, line: __ENV__.line]
      Util.merge(unquote(state.quoted), :on, on)
    end
    state.quoted(quoted)
  end

  defp build_query_type({ type, expr }, KwState[] = state) when type in [:limit, :offset, :preload] do
    state.quoted(quote do
      Ecto.Query.unquote(type)(unquote(state.quoted), unquote(expr))
    end)
  end

  defp build_query_type({ type, expr }, KwState[] = state) do
    state.quoted(quote do
      Ecto.Query.unquote(type)(unquote(state.quoted), unquote(state.binds), unquote(expr))
    end)
  end

  defp build_join(qual, expr, KwState[] = state) do
    { binds, expr } = JoinBuilder.escape(expr, state.binds)
    if (bind = Enum.first(binds)) && bind != :_ && bind in state.binds do
      raise Ecto.QueryError, reason: "variable `#{bind}` is already defined in query"
    end

    is_assoc = Ecto.Associations.assoc_join?(expr)

    quoted = quote do
      qual = unquote(qual)
      expr = unquote(expr)
      if unquote(is_assoc) do
        join = AssocJoinExpr[qual: qual, expr: expr, file: __ENV__.file, line: __ENV__.line]
      else
        join = JoinExpr[qual: qual, source: expr, file: __ENV__.file, line: __ENV__.line]
      end
      Util.merge(unquote(state.quoted), :join, join)
    end
    state.quoted(quoted).binds(state.binds ++ [bind])
  end
end
