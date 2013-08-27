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
  multiple `where`s can be given. `select` selects which results will be
  returned, a single variable can be given, that will return the full entity, or
  a single field. Multiple fields can also be grouped in lists or tuples. Only
  one `select` expression is allowed.

  External variables and elixir expressions can be injected into a query
  expression with `^`. Anything that isn't inside a `^` expression is treated
  as a query expression.

  This allows one to create dynamic queries:

      def with_minimum(age, height_ft) do
        from u in User,
        where: u.age > ^age and u.height > ^(height_ft * 3.28)
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

  @type t :: Query.t

  defrecord Query, entities: nil, from: nil, joins: [], wheres: [], select: nil,
                   order_bys: [], limit: nil, offset: nil, group_bys: [], havings: [],
                   preloads: []

  defrecord QueryExpr, [:expr, :file, :line]
  defrecord AssocJoinExpr, [:qual, :expr, :file, :line]
  defrecord JoinExpr, [:qual, :entity, :on, :file, :line]

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
      Util.merge(unquote(query), :from, unquote(expr))
    end
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
    { _binds, expr } = FromBuilder.escape(expr)
    expr
  end

  @doc """
  A join query expression. Receives an entity that is to be joined to the query
  and a condition to do the joining on. The join condition can be any expression
  that evaluates to a boolean value. The join is by default an inner join, the
  qualifier can be changed by giving the atoms: `:inner`, `:left`, `:right` or
  `:full`. For a keyword query the `:join` keyword can be changed to:
  `:inner_join`, `:left_join`, `:right_join` or `:full_join`.

  The join condition can be automatically set when doing an association join. An
  association join can be done on any association field (`has_many`, `has_one`,
  `belong_to`).

  ## Keywords examples

         from c in Comment,
        join: p in Post, on: c.post_id == p.id,
      select: { p.title, c.text }

         from p in Post,
        left_join: c in p.comments,
      select: { p, c }

  ## Expressions examples

      from(Comment)
        |> join([c], p in Post, c.post_id == p.id)
        |> select([c, p], { p.title, c.text })

      from(Post)
        |> join([p], :left, c in p.comments)
        |> select([p, c], { p, c })
  """
  defmacro join(query, binding, qual // nil, expr, on // nil) do
    binding = Util.escape_binding(binding)
    { expr_bindings, join_expr } = JoinBuilder.escape(expr, binding)

    is_assoc = Ecto.Associations.assoc_join?(join_expr)
    unless is_assoc == nil?(on) do
      raise Ecto.InvalidQuery, reason: "`join` expression requires explicit `on` " <>
        "expression unless association join expression"
    end
    if (bind = Enum.first(expr_bindings)) && bind in binding do
      raise Ecto.InvalidQuery, reason: "variable `#{bind}` is already defined in query"
    end

    on_expr = if on do
      binding = binding ++ expr_bindings
      WhereBuilder.escape(on, binding)
    end

    quote do
      qual = unquote(qual)
      join_expr = unquote(join_expr)
      if unquote(is_assoc) do
        join = AssocJoinExpr[qual: qual, expr: join_expr, file: __ENV__.file, line: __ENV__.line]
      else
        on = QueryExpr[expr: unquote(on_expr), file: __ENV__.file, line: __ENV__.line]
        join = JoinExpr[qual: qual, entity: join_expr, on: on, file: __ENV__.file, line: __ENV__.line]
      end
      Util.merge(unquote(query), :join, join)
    end
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

  The `assoc/2` selector can be used to load an association on a parent entity
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
    binding = Util.escape_binding(binding)
    quote do
      select_expr = unquote(SelectBuilder.escape(expr, binding))
      select = QueryExpr[expr: select_expr, file: __ENV__.file, line: __ENV__.line]
      Util.merge(unquote(query), :select, select)
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
    binding = Util.escape_binding(binding)
    quote do
      where_expr = unquote(WhereBuilder.escape(expr, binding))
      where = QueryExpr[expr: where_expr, file: __ENV__.file, line: __ENV__.line]
      Util.merge(unquote(query), :where, where)
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
    binding = Util.escape_binding(binding)
    quote do
      expr = unquote(OrderByBuilder.escape(expr, binding))
      order_by = QueryExpr[expr: expr, file: __ENV__.file, line: __ENV__.line]
      Util.merge(unquote(query), :order_by, order_by)
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
  defmacro limit(query, _binding // [], expr) do
    quote do
      expr = unquote(expr)
      LimitOffsetBuilder.validate(expr)
      Util.merge(unquote(query), :limit, expr)
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
  defmacro offset(query, _binding // [], expr) do
    quote do
      expr = unquote(expr)
      LimitOffsetBuilder.validate(expr)
      Util.merge(unquote(query), :offset, expr)
    end
  end

  @doc """
  A group by query expression. Groups together rows from the entity that have
  the same values in the given fields. Using `group_by` "groups" the query
  giving it different semantics in the `select` expression. If a query is
  grouped only fields that were referenced in the `group_by` can be used in the
  `select` or if the field is given as an argument to an aggregate function.

  ## Keywords examples

      # Returns the number of posts in each category
      from(p in Post,
        group_by: p.category,
        select: { p.category, count(p.id) })

  ## Expressions examples

      from(Post) |> group_by([p], p.category) |> select([p], count(p.id))

  """
  defmacro group_by(query, binding, expr) do
    binding = Util.escape_binding(binding)
    quote do
      expr = unquote(GroupByBuilder.escape(expr, binding))
      group_by = QueryExpr[expr: expr, file: __ENV__.file, line: __ENV__.line]
      Util.merge(unquote(query), :group_by, group_by)
    end
  end

  @doc """
  A having query expression. Like `where` `having` filters rows from the entity,
  but after the grouping is performed giving it the same semantics as `select`
  for a grouped query (see `group_by/3`). `having` groups the query even if the
  query has no `group_by` expression.

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
    binding = Util.escape_binding(binding)
    quote do
      having_expr = unquote(HavingBuilder.escape(expr, binding))
      having = QueryExpr[expr: having_expr, file: __ENV__.file, line: __ENV__.line]
      Util.merge(unquote(query), :having, having)
    end
  end

  @doc """
    A preload query expression. Preloads the specified fields on the entity in the
  from expression. Loads all associated records for each entity in the result
  set based on the association. The fields have to be association fields and the
  entity has to be in the select expression.

  ## Keywords examples

      # Returns all posts and their associated comments
      from(p in Post,
        preload: [:comments],
        select: p)

  ## Expressions examples

      from(Post) |> preload(:comments) |> select([p], p)
  """
  defmacro preload(query, _binding // [], expr) do
    expr = List.wrap(expr)
    PreloadBuilder.validate(expr)
    quote do
      preload_expr = unquote(expr)
      preload = QueryExpr[expr: preload_expr, file: __ENV__.file, line: __ENV__.line]
      Util.merge(unquote(query), :preload, preload)
    end
  end

  defrecord KwState, [:quoted, :binds]

  # Builds the quoted code for creating a keyword query
  defp build_query(quoted, binds, kw) do
    state = KwState[quoted: quoted, binds: binds]
    Enum.reduce(kw, state, &build_query_type(&1, &2)).quoted
  end

  defp build_query_type({ :from, expr }, KwState[] = state) do
    FromBuilder.validate_query_from(expr)
    { [bind], expr } = FromBuilder.escape(expr)
    if bind != :_ and bind in state.binds do
      raise Ecto.InvalidQuery, reason: "variable `#{bind}` is already defined in query"
    end

    quoted = quote do
      Util.merge(unquote(state.quoted), :from, unquote(expr))
    end
    state.quoted(quoted).binds(state.binds ++ [bind])
  end

  @joins [:join, :inner_join, :left_join, :right_join, :full_join]

  defp build_query_type({ join, expr }, state) when join in @joins do
    case join do
      :join       -> build_join(nil, expr, state)
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

  defp build_query_type({ type, expr }, KwState[] = state) do
    quoted = quote do
      Ecto.Query.unquote(type)(unquote(state.quoted), unquote(state.binds), unquote(expr))
    end
    state.quoted(quoted)
  end

  defp build_join(qual, expr, KwState[] = state) do
    { binds, expr } = JoinBuilder.escape(expr, state.binds)
    if (bind = Enum.first(binds)) && bind != :_ && bind in state.binds do
      raise Ecto.InvalidQuery, reason: "variable `#{bind}` is already defined in query"
    end

    is_assoc = Ecto.Associations.assoc_join?(expr)

    quoted = quote do
      qual = unquote(qual)
      expr = unquote(expr)
      if unquote(is_assoc) do
        join = AssocJoinExpr[qual: qual, expr: expr, file: __ENV__.file, line: __ENV__.line]
      else
        join = JoinExpr[qual: qual, entity: expr, file: __ENV__.file, line: __ENV__.line]
      end
      Util.merge(unquote(state.quoted), :join, join)
    end
    state.quoted(quoted).binds(state.binds ++ [bind])
  end
end
