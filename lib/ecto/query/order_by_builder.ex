defmodule Ecto.Query.OrderByBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  @doc """
  Escapes an order by query.

  The query is escaped to a list of `{ direction, var, field }`
  pairs at runtime. Escaping also validates direction is one of
  `:asc` or `:desc`.

  ## Examples

      iex> escape(quote do [x.x, y.y] end, [:x, :y])
      [{ :{}, [], [:asc, { :{}, [], [:&, [], [0]] }, :x] },
       { :{}, [], [:asc, { :{}, [], [:&, [], [1]] }, :y] }]

  """
  @spec escape(Macro.t, [atom]) :: Macro.t
  def escape(list, vars) when is_list(list) do
    Enum.map(list, &escape_field(&1, vars))
  end

  def escape(field, vars) do
    [escape_field(field, vars)]
  end

  defp escape_field({ dir, { :., _, [{ var, _, context }, field] } }, vars)
      when is_atom(var) and is_atom(context) and is_atom(field) do
    check_dir(dir)
    var_escaped = BuilderUtil.escape_var(var, vars)
    { :{}, [], [dir, var_escaped, Macro.escape(field)] }
  end

  defp escape_field({ dir, { :field, _, [{ var, _, context }, field] } }, vars)
      when is_atom(var) and is_atom(context) do
    check_dir(dir)
    var_escaped = BuilderUtil.escape_var(var, vars)
    field_escaped = BuilderUtil.escape(field, vars)
    { :{}, [], [dir, var_escaped, field_escaped] }
  end

  defp escape_field({ dir, { { :., _, _ } = dot, _, [] } }, vars) do
    escape_field({ dir, dot }, vars)
  end

  defp escape_field({ _, _ }, _vars) do
    raise Ecto.QueryError, reason: "malformed order_by query"
  end

  defp escape_field(ast, vars) do
    escape_field({ :asc, ast }, vars)
  end

  defp check_dir(dir) when dir in [:asc, :desc], do: :ok
  defp check_dir(dir) do
    reason = "non-allowed direction `#{dir}`, only `asc` and `desc` allowed"
    raise Ecto.QueryError, reason: reason
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(query, binding, expr, env) do
    binding  = BuilderUtil.escape_binding(binding)
    expr     = escape(expr, binding)
    order_by = Ecto.Query.QueryExpr[expr: expr, file: env.file, line: env.line]
    BuilderUtil.apply_query(query, __MODULE__, [order_by], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.Query.t
  def apply(query, expr) do
    Ecto.Query.Query[order_bys: order_bys] = query = Ecto.Queryable.to_query(query)
    query.order_bys(order_bys ++ [expr])
  end
end
