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

  defrecord Query, froms: [], wheres: [], select: nil
  defrecord QueryExpr, expr: nil, binding: [], file: nil, line: nil

  alias Ecto.Query.FromBuilder
  alias Ecto.Query.WhereBuilder
  alias Ecto.Query.SelectBuilder

  @doc """
  Extends an existing a query by appending the given expressions to it. Takes a
  list of bound variables that will rebind the variables from the original query
  to their new names. The bindings are order dependent, that means that each
  variable will be bound to the variable in the original query that was defined
  in the same order as the binding was in its list.
  """
  defmacro extend(original, bindings, kw) when is_list(kw) do
    build_query(original, bindings, kw, __CALLER__)
  end

  @doc """
  Creates a query. See the module documentation for more information and
  examples.
  """
  defmacro from(query // Macro.escape(Query[]), expr)

  defmacro from({ :in, _, [_, _] } = from, kw) when is_list(kw) do
    caller = __CALLER__
    query = Macro.escape(Query[])
    { var, _ } = from_expr = FromBuilder.escape(from, caller)
    quoted = quote do
      Ecto.Query.merge(unquote(query), :from, unquote(from_expr))
    end

    build_query(quoted, [var], kw, caller)
  end

  defmacro from(query, expr) do
    # TODO: change syntax: x in X -> X
    from_expr = FromBuilder.escape(expr, __CALLER__)
    quote do
      Ecto.Query.merge(unquote(query), :from, unquote(from_expr))
    end
  end

  @doc false
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

  @doc false
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
  Validates the query to check if it is correct. Should be called before
  compilation by the query adapter.
  """
  def validate(query) do
    Ecto.Query.Validator.validate(query)
  end

  @doc false
  def merge(left, right) do
    check_merge(left, right)

    Query[ froms: left.froms ++ right.froms,
           wheres: left.wheres ++ right.wheres,
           select: right.select ]
  end

  @doc false
  def merge(query, type, expr) do
    check_merge(query, Query.new([{ type, expr }]))

    case type do
      :from   -> query.update_froms(&1 ++ [expr])
      :where  -> query.update_wheres(&1 ++ [expr])
      :select -> query.select(expr)
    end
  end

  defp build_query(quoted, vars, kw, env) do
    unless Keyword.keyword?(kw) do
      raise ArgumentError, message: "second argument to from has to be a keyword list"
    end

    { quoted, _ } =
      Enum.reduce(kw, { quoted, vars }, fn({ type, expr }, { quoted, vars }) ->
        case type do
          :from ->
            { var, _ } = from_expr = FromBuilder.escape(expr, env)
            quoted = quote do
              Ecto.Query.merge(unquote(quoted), :from, unquote(from_expr))
            end
            if var in vars do
              raise ArgumentError, message: "variable `#{var}` is already defined"
            end
            { quoted, vars ++ [var] }

          :select ->
            quoted = quote do
              Ecto.Query.select(unquote(quoted), unquote(vars), unquote(expr))
            end
            { quoted, vars }

          :where ->
            quoted = quote do
              Ecto.Query.where(unquote(quoted), unquote(vars), unquote(expr))
            end
            { quoted, vars }
        end
      end)
    quoted
  end

  defp check_merge(left, right) do
    if left.select && right.select do
      raise ArgumentError, message: "only one select expression is allowed in query"
    end
  end

  defp escape_binding(var) when is_atom(var) do
    var
  end

  defp escape_binding({ var, _, context }) when is_atom(var) and is_atom(context) do
    var
  end

  defp escape_binding(_) do
    raise ArgumentError, message: "binding should be list of variables"
  end
end
