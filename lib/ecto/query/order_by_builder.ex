defmodule Ecto.Query.OrderByBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  @doc """
  Escapes an order by query.

  The query is escaped to a list of `{direction, var, field}`
  pairs at runtime. Escaping also validates direction is one of
  `:asc` or `:desc`.

  ## Examples

      iex> escape(quote do [x.x, y.y] end, [x: 0, y: 1])
      [{:{}, [], [:asc, {:{}, [], [:&, [], [0]]}, :x]},
       {:{}, [], [:asc, {:{}, [], [:&, [], [1]]}, :y]}]

  """
  @spec escape(Macro.t, Keyword.t) :: Macro.t | no_return
  def escape(list, vars) when is_list(list) do
    Enum.map(list, &escape_field(&1, vars))
  end

  def escape(field, vars) do
    [escape_field(field, vars)]
  end

  defp escape_field({dir, dot}, vars) do
    check_dir(dir)
    case BuilderUtil.escape_dot(dot, vars) do
      {var, field} ->
        {:{}, [], [dir, var, field]}
      :error ->
        raise Ecto.QueryError, reason: "malformed `order_by` query expression"
    end
  end

  defp escape_field(ast, vars) do
    escape_field({:asc, ast}, vars)
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
    order_by = quote do: %Ecto.Query.QueryExpr{expr: unquote(expr),
                         file: unquote(env.file), line: unquote(env.line)}
    BuilderUtil.apply_query(query, __MODULE__, [order_by], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.t
  def apply(query, expr) do
    query = Ecto.Queryable.to_query(query)
    %{query | order_bys: query.order_bys ++ [expr]}
  end
end
