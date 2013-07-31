defmodule Ecto.Query do
  @moduledoc """
  This module is the query DSL. Queries are used to fetch data from a repository
  (see `Ecto.Repo`).

  ## Examples

      import Ecto.Query

         from w in Weather,
       where: w.prcp > 0,
      select: w.city

  The above example will create a query that can be run against a repository.
  `from` will bind the variable `w` to the entity `Weather` (see `Ecto.Entity`).
  If there are multiple from expressions the query will run for every
  permutation of their combinations. `where` is used to filter the results,
  multiple `where`s can be given. `select` selects which results will be returned,
  a single variable can be given, that will return the full entity, or a single
  field. Multiple fields can also be grouped in lists or tuples. Only one
  `select` expression is allowed.

  Every variable that isn't bound in a query expression and every function or
  operator that aren't query operators or functions will be treated as Elixir
  code and their evaluated result will be inserted into the query.

  This allows one to create dynamic queries:

      def with_minimum_age(age) do
        from u in User, where: u.age > age
      end

  In the example above, we will compare against the `age` given as argument.
  Notice the `select` clause is optional, Ecto will automatically infer and
  returns the user record (similar to `select: u`) from the query above.

  ## Extensions

  Queries are composable and can be extend dynamically. This allows you to
  create specific queries given a parameter:

      query = from w in Weather, select: w.city
      if filter_by_prcp do
        query = extend w in query, where: w.prcp > 0
      end
      Repo.all(query)

  Or even create functions that extend an existing query:

      def paginate(query, page, size) do
        extend query,
          limit: size,
          offset: (page-1) * size
      end

      query |> paginate |> Repo.all

  ## Query expansion

  In the examples above, we have used the so-called **keywords query syntax**
  to create a query. Our first example:

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

  # TODO: Add query operators (and functions?) to documentation

  @type t :: Query.t

  defrecord Query, froms: [], wheres: [], select: nil, order_bys: [],
                   limit: nil, offset: nil, group_bys: [], havings: []
  defrecord QueryExpr, expr: nil, binding: [], file: nil, line: nil

  alias Ecto.Query.FromBuilder
  alias Ecto.Query.WhereBuilder
  alias Ecto.Query.SelectBuilder
  alias Ecto.Query.OrderByBuilder
  alias Ecto.Query.LimitOffsetBuilder
  alias Ecto.Query.GroupByBuilder
  alias Ecto.Query.HavingBuilder
  alias Ecto.Query.QueryUtil

  @doc """
  Creates a query. It can either be a keyword query or a query expression. If it
  is a keyword query the first argument should be an `in` expression and the
  second argument a keyword query where they keys are expression types and the
  values are expressions.

  If it is a query expression the first argument is the original query and the
  second argument the expression.

  ## Keywords examples

      from(City, select: c)

  ## Expressions examples

      from(City) |> select([c], c)

  # Extending queries

  An existing query can be extended with `from` by appending the given
  expressions to it.

  The existing variables from the original query can be rebound by
  giving the variables on the left hand side of `in`. The bindings
  are order dependent, that means that each variable will be bound to
  the variable in the original query that was defined in the same order
  as the binding was in its list.

  ## Examples

      def paginate(query, page, size) do
        from query,
          limit: size,
          offset: (page-1) * size
      end

  The example above does not rebinding any variable, as they are not
  required for `limit` and `offset`. However, extending a query with
  where expression would require so:

      def published(query) do
        from p in query, where: p.published_at != nil
      end

  Notice we have rebound the term `p`. In case the given query has
  more than one `from` expression, each of them must be given in
  the order they were bound:

      def published_multi(query) do
        from [p,o] in query,
        where: p.published_at != nil and o.published_at != nil
      end
  """
  defmacro from(expr, kw) when is_list(kw) do
    unless Keyword.keyword?(kw) do
      raise Ecto.InvalidQuery, reason: "second argument to from has to be a keyword list"
    end

    { binds, expr } = FromBuilder.escape(expr)
    build_query(expr, binds, kw)
  end

  defmacro from(query, expr) do
    FromBuilder.validate_query_from(expr)
    { _binds, expr } = FromBuilder.escape(expr)
    quote do
      QueryUtil.merge(unquote(query), :from, unquote(expr))
    end
  end

  @doc """
  Creates a query with a from query expression.

  ## Examples

      from(c in City)

  """
  defmacro from(expr) do
    { _binds, expr } = FromBuilder.escape(expr)
    expr
  end

  @doc """
  A select query expression. Selects which fields will be selected from the
  entity and any transformations that should be performed on the fields, any
  expression that is accepted in a query can be a select field. There can only
  be one select expression in a query, if the select expression is omitted, the
  query will by default select the full entity (only works when there is a
  single from expression and no group by).

  The sub-expressions in the query can be wrapped in lists or tuples as shown in
  the examples. A full entity can also be selected if the entity variable is the
  only thing in the expression.

  ## Keywords examples

      from(c in City, select: c) # selects the entire entity
      from(c in City, select: { c.name, c.population })
      from(c in City, select: [c.name, c.county])
      from(c in City, select: { c.name, to_binary(40 + 2), 43 })

  ## Expressions examples

      from(c in City) |> select([c], c)
      from(c in City) |> select([c], { c.name, c.country })

  """
  defmacro select(query, binding, expr) do
    binding = QueryUtil.escape_binding(binding)
    quote do
      select_expr = unquote(SelectBuilder.escape(expr, binding))
      select = QueryExpr[expr: select_expr, binding: unquote(binding),
                         file: __ENV__.file, line: __ENV__.line]
      QueryUtil.merge(unquote(query), :select, select)
    end
  end

  @doc """
  A where query expression. Filters the rows from the entity. If there are more
  than one where expressions they will be combined in conjunction. A where
  expression have to evaluate to a boolean value.

  ## Keywords examples

      from(c in City, where: c.state == "Sweden")

  ## Expressions examples

      from(c in City) |> where([c], c.state == "Sweden")

  """
  defmacro where(query, binding, expr) do
    binding = QueryUtil.escape_binding(binding)
    quote do
      where_expr = unquote(WhereBuilder.escape(expr, binding))
      where = QueryExpr[expr: where_expr, binding: unquote(binding),
                        file: __ENV__.file, line: __ENV__.line]
      QueryUtil.merge(unquote(query), :where, where)
    end
  end

  @doc """
  An order by query expression. Orders the fields based on one or more entity
  fields. It accepts a single field or a list field, the direction can be
  specified in a keyword list as shown in the examples. There can be several
  order by expressions in a query.

  ## Keywords examples

      from(c in City, order_by: c.name, order_by: c.population)
      from(c in City, order_by: [c.name, c.population])
      from(c in City, order_by: [asc: c.name, desc: c.population])

  ## Expressions examples

      from(c in City) |> order_by([c], asc: c.name, desc: c.population)

  """
  defmacro order_by(query, binding, expr)  do
    binding = QueryUtil.escape_binding(binding)
    quote do
      order_expr = unquote(OrderByBuilder.escape(expr, binding))
      order = QueryExpr[expr: order_expr, binding: unquote(binding)]
      QueryUtil.merge(unquote(query), :order_by, order)
    end
  end

  @doc """
  A limit query expression. Limits the number of rows selected from the entity.
  Can be any expression but have to evaluate to an integer value. Can't include
  entity fields.

  ## Keywords examples

      from(u in User, where: u.id == current_user, limit: 1)

  ## Expressions examples

      from(u in User) |> where(u.id == current_user) |> limit(1)

  """
  defmacro limit(query, binding // [], expr) do
    binding = QueryUtil.escape_binding(binding)
    quote do
      limit_expr = unquote(LimitOffsetBuilder.escape(expr, binding))
      LimitOffsetBuilder.validate(limit_expr)
      limit = QueryExpr[expr: limit_expr, binding: unquote(binding),
                        file: __ENV__.file, line: __ENV__.line]
      QueryUtil.merge(unquote(query), :limit, limit)
    end
  end

  @doc """
  An offset query expression. Limits the number of rows selected from the
  entity. Can be any expression but have to evaluate to an integer value.
  Can't include entity fields.

  ## Keywords examples

      # Get all posts on page 4
      from(p in Post, limit: 10, offset: 30)

  ## Expressions examples

      from(p in Post) |> limit(10) |> offset(30)

  """
  defmacro offset(query, binding // [], expr) do
    binding = QueryUtil.escape_binding(binding)
    quote do
      offset_expr = unquote(LimitOffsetBuilder.escape(expr, binding))
      LimitOffsetBuilder.validate(offset_expr)
      offset = QueryExpr[expr: offset_expr, binding: unquote(binding),
                         file: __ENV__.file, line: __ENV__.line]
      QueryUtil.merge(unquote(query), :offset, offset)
    end
  end

  @doc """
  TODO
  """
  defmacro group_by(query, binding, expr) do
    binding = QueryUtil.escape_binding(binding)
    quote do
      group_expr = unquote(GroupByBuilder.escape(expr, binding))
      order = QueryExpr[expr: group_expr, binding: unquote(binding)]
      QueryUtil.merge(unquote(query), :group_by, order)
    end
  end

  @doc """
  TODO
  """
  defmacro having(query, binding, expr) do
    binding = QueryUtil.escape_binding(binding)
    quote do
      having_expr = unquote(HavingBuilder.escape(expr, binding))
      having = QueryExpr[expr: having_expr, binding: unquote(binding)]
      QueryUtil.merge(unquote(query), :having, having)
    end
  end

  # Builds the quoted code for creating a keyword query
  defp build_query(quoted, binds, kw) do
    Enum.reduce(kw, { quoted, binds }, &build_query_type(&1, &2))
      |> elem(0)
  end

  defp build_query_type({ :from, expr }, { quoted, binds }) do
    { [bind], expr } = FromBuilder.escape(expr)
    if bind != :_ and bind in binds do
      raise Ecto.InvalidQuery, reason: "variable `#{bind}` is already defined in query"
    end

    quoted = quote do
      QueryUtil.merge(unquote(quoted), :from, unquote(expr))
    end
    { quoted, binds ++ [bind] }
  end

  defp build_query_type({ type, expr }, { quoted, binds }) do
    quoted = quote do
      Ecto.Query.unquote(type)(unquote(quoted), unquote(binds), unquote(expr))
    end
    { quoted, binds }
  end
end
