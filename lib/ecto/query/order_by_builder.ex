defmodule Ecto.Query.OrderByBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  @doc """
  Escapes an order by query.

  The query is escaped to a list of `{direction, expression}`
  pairs at runtime. Escaping also validates direction is one of
  `:asc` or `:desc`.

  ## Examples

      iex> escape(quote do [x.x, foo()] end, [x: 0])
      [asc: {:{}, [], [{:{}, [], [:., [], [{:{}, [], [:&, [], [0]]}, :x]]}, [], []]},
       asc: {:{}, [], [:foo, [], []]}]

  """
  @spec escape(Macro.t, Keyword.t) :: Macro.t
  def escape(expr, vars) do
    List.wrap(expr)
    |> Enum.map(&do_escape(&1, vars))
  end

  defp do_escape({dir, expr}, vars) do
    check_dir(dir)
    ast = BuilderUtil.escape(expr, vars)
    {dir, ast}
  end

  defp do_escape(expr, vars) do
    {:asc, BuilderUtil.escape(expr, vars)}
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
