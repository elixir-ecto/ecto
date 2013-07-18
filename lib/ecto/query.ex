defmodule Ecto.Query do
  @moduledoc """
  This module is the query DSL. Queries are used to fetch data from a repository
  (see `Ecto.Repo`).

  ## Example

         from w in Weather,
       where: w.prcp > 0,
      select: w.city

  The above example will create a query that can be run against a repository.
  `from` will bind the variable `w` to the entity `Weather` (see `Ecto.Entity`).
  If there are multiple from expressions the query will run for every
  permutation of their combinations. `where` specifies a relation that will hold
  all the results, multiple `where`s can be given. `select` selects which
  results will be returned, a single variable can be given, that will return the
  full entity, or a single field. Multiple fields can also be grouped in lists
  or tuples. Only one `select` expression is allowed.

  Every variable that isn't bound in a query expression and every function or
  operator that aren't query operators or functions will be treated as elixir
  code and their evaluated result will be inserted into the query.
  """

  # TODO: Add query operators (and functions?) to documentation

  defrecord Query, froms: [], wheres: [], select: nil, order_bys: [],
                   limit: nil, offset: nil
  defrecord QueryExpr, expr: nil, binding: [], file: nil, line: nil

  alias Ecto.Query.FromBuilder
  alias Ecto.Query.WhereBuilder
  alias Ecto.Query.SelectBuilder
  alias Ecto.Query.OrderByBuilder
  alias Ecto.Query.LimitOffsetBuilder

  @doc """
  Extends an existing a query by appending the given expressions to it. Takes an
  optional list of bound variables that will rebind the variables from the
  original query to their new names. The bindings are order dependent, that
  means that each variable will be bound to the variable in the original query
  that was defined in the same order as the binding was in its list.

  ## Example
      def paginate(query, page, size) do
        extend query,
          limit: size,
          offset: (page-1) * size
      end
  """
  defmacro extend(original, bindings // [], kw) when is_list(kw) do
    build_query(original, bindings, kw, __CALLER__)
  end

  @doc false
  defmacro from(query, binding, expr) do
    # TODO: change syntax: 'from(x in X)' -> 'from(X)'
    from_expr = FromBuilder.escape(expr, binding, __CALLER__)
    quote do
      Ecto.Query.merge(unquote(query), :from, unquote(from_expr))
    end
  end

  @doc """
  Creates a query. It can either be a keyword query or a query expression. If it
  is a keyword query the first argument should be an `in` expression and the
  second argument a keyword query where they keys are expression types and the
  values are expressions.

  If it is a query expression the first argument is the original query and the
  second argument the expression.

  ## Examples
      from(c in City, select: c)

      from(c in City) |> select([c], c)
  """
  defmacro from({ :in, _, [_, _] } = from, kw) when is_list(kw) do
    caller = __CALLER__
    query = Macro.escape(Query[])
    { var, _ } = from_expr = FromBuilder.escape(from, [], caller)
    quoted = quote do
      Ecto.Query.merge(unquote(query), :from, unquote(from_expr))
    end

    build_query(quoted, [var], kw, caller)
  end

  defmacro from(query, expr) do
    quote do
      from(unquote(query), [], unquote(expr))
    end
  end

  @doc """
  Creates a query with a from query expression. See `query/2` from more
  information.
  """
  defmacro from(expr) do
    quote do
      from(Query[], [], unquote(expr))
    end
  end

  @doc """
  A select query expression. Selects which fields will be selected from the
  entity and any transformations that should be performed on the fields, any
  qexpression that is accepted in a query can be a slect field. There can only
  be one select expression in a query, if the select expression is omitted, the
  query will by default select the full entity (only works when there is a
  single from expression and no group by).

  The sub-expressions in the query can be wrapped in lists or tuples as shown in
  the examples. A full entity can also be selected if the entity variable is the
  only thing in the expression.

  ## Examples
      from(c in City, select: c) # selects the entire entity
      from(c in City, select: { c.name, c.population })
      from(c in City, select: [c.name, c.county])
      from(c in City, select: { c.name, to_binary(40 + 2), 43 })
  """
  defmacro select(query // Macro.escape(Query[]), binding, expr)
      when is_list(binding) do
    binding = Enum.map(binding, escape_binding(&1))
    quote do
      select_expr = unquote(SelectBuilder.escape(expr, binding))
      select = QueryExpr[expr: select_expr, binding: unquote(binding),
                         file: __ENV__.file, line: __ENV__.line]
      Ecto.Query.merge(unquote(query), :select, select)
    end
  end

  @doc """
  A where query expression. Filters the rows from the entity. If there are more
  than one where expressions they will be combined in conjunction. A where
  expression have to evaluate to a boolean value.

  ## Examples
      from(c in City, where: c.state == "Sweden")
  """
  defmacro where(query // Macro.escape(Query[]), binding, expr)
      when is_list(binding) do
    binding = Enum.map(binding, escape_binding(&1))
    quote do
      where_expr = unquote(WhereBuilder.escape(expr, binding))
      where = QueryExpr[expr: where_expr, binding: unquote(binding),
                        file: __ENV__.file, line: __ENV__.line]
      Ecto.Query.merge(unquote(query), :where, where)
    end
  end

  @doc """
  An order by query expression. Orders the fields based on one or more entity
  fields. It accepts a single field or a list field, the direction can be
  specified in a keyword list as shown in the examples. There can be several
  order by expressions in a query.

  ## Examples
      from(c in City, order_by: c.name, order_by: c.population)
      from(c in City, order_by: [c.name, c.population])
      from(c in City, order_by: [asc: c.name, desc: c.population])
  """
  defmacro order_by(query // Macro.escape(Query[]), binding, expr)
      when is_list(binding) do
    binding = Enum.map(binding, escape_binding(&1))
    quote do
      order_by_expr = unquote(OrderByBuilder.escape(expr, binding))
      order_by = QueryExpr[expr: order_by_expr, binding: unquote(binding)]
      Ecto.Query.merge(unquote(query), :order_by, order_by)
    end
  end

  @doc """
  A limit query expression. Limits the number of rows selected from the entity.
  Can be any expression but have to evaluate to an integer value. Can't include
  entity fields.

  ## Examples
      from(u in User, where: u.id == current_user, limit: 1)
  """
  defmacro limit(query // Macro.escape(Query[]), binding, expr)
      when is_list(binding) do
    binding = Enum.map(binding, escape_binding(&1))
    quote do
      limit_expr = unquote(LimitOffsetBuilder.escape(expr, binding))
      LimitOffsetBuilder.validate(limit_expr)
      limit = QueryExpr[expr: limit_expr, binding: unquote(binding),
                        file: __ENV__.file, line: __ENV__.line]
      Ecto.Query.merge(unquote(query), :limit, limit)
    end
  end

  @doc """
  An offset query expression. Limits the number of rows selected from the
  entity. Can be any expression but have to evaluate to an integer value. Can't include
  entity fields.

  ## Examples
      # Get all posts on page 4
      from(p in Post, limit: 10, offset: 30)
  """
  defmacro offset(query // Macro.escape(Query[]), binding, expr)
      when is_list(binding) do
    binding = Enum.map(binding, escape_binding(&1))
    quote do
      offset_expr = unquote(LimitOffsetBuilder.escape(expr, binding))
      LimitOffsetBuilder.validate(offset_expr)
      offset = QueryExpr[expr: offset_expr, binding: unquote(binding),
                         file: __ENV__.file, line: __ENV__.line]
      Ecto.Query.merge(unquote(query), :offset, offset)
    end
  end

  @doc """
  Validates the query to check if it is correct. Should be called before
  compilation by the query adapter.
  """
  def validate(query) do
    Ecto.Query.Validator.validate(query)
  end

  @doc """
  Normalizes the query. Should be called before
  compilation by the query adapter.
  """
  def normalize(query) do
    Ecto.Query.Normalizer.normalize(query)
  end

  # Merges two keyword queries
  @doc false
  def merge(Query[] = left, Query[] = right) do
    check_merge(left, right)

    Query[ froms:     left.froms ++ right.froms,
           wheres:    left.wheres ++ right.wheres,
           select:    right.select,
           order_bys: left.order_bys ++ right.order_bys,
           limit:     right.limit,
           offset:    right.offset ]
  end

  # Merges a keyword query with a query expression
  @doc false
  def merge(Query[] = query, type, expr) do
    check_merge(query, Query.new([{ type, expr }]))

    case type do
      :from     -> query.update_froms(&1 ++ [expr])
      :where    -> query.update_wheres(&1 ++ [expr])
      :select   -> query.select(expr)
      :order_by -> query.update_order_bys(&1 ++ [expr])
      :limit    -> query.limit(expr)
      :offset   -> query.offset(expr)
    end
  end

  # Builds the quoted code for creating a keyword query, used by extend and from
  defp build_query(quoted, vars, kw, env) do
    unless Keyword.keyword?(kw) do
      raise Ecto.InvalidQuery, reason: "second argument to from has to be a keyword list"
    end

    { quoted, _ } =
      Enum.reduce(kw, { quoted, vars }, fn({ type, expr }, { quoted, vars }) ->
        case type do
          :from ->
            { var, _ } = from_expr = FromBuilder.escape(expr, vars, env)
            quoted = quote do
              Ecto.Query.merge(unquote(quoted), :from, unquote(from_expr))
            end
            { quoted, vars ++ [var] }

          type ->
            quoted = quote do
              Ecto.Query.unquote(type)(unquote(quoted), unquote(vars), unquote(expr))
            end
            { quoted, vars }
        end
      end)
    quoted
  end

  # Checks if a keyword query merge can be done
  defp check_merge(Query[] = left, Query[] = right) do
    if left.select && right.select do
      raise Ecto.InvalidQuery, reason: "only one select expression is allowed in query"
    end

    if left.limit && right.limit do
      raise Ecto.InvalidQuery, reason: "only one limit expression is allowed in query"
    end

    if left.offset && right.offset do
      raise Ecto.InvalidQuery, reason: "only one offset expression is allowed in query"
    end
  end

  defp escape_binding(var) when is_atom(var) do
    var
  end

  defp escape_binding({ var, _, context }) when is_atom(var) and is_atom(context) do
    var
  end

  defp escape_binding(_) do
    raise Ecto.InvalidQuery, reason: "binding should be list of variables"
  end
end
