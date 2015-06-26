defmodule Ecto.Query.Builder.GroupBy do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Escapes a list of quoted expressions.

  See `Ecto.Builder.escape/2`.

      iex> escape(quote do [x.x, 13] end, [x: 0], __ENV__)
      {[{:{}, [], [{:{}, [], [:., [], [{:{}, [], [:&, [], [0]]}, :x]]}, [], []]},
        13],
       %{}}
  """
  @spec escape(Macro.t, Keyword.t, Macro.Env.t) :: Macro.t
  def escape(expr, vars, env) do
    expr
    |> List.wrap
    |> Builder.escape(:any, %{}, vars, env)
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(query, binding, expr, env) do
    binding        = Builder.escape_binding(binding)
    {expr, params} = escape(expr, binding, env)
    params         = Builder.escape_params(params)

    group_by = quote do: %Ecto.Query.QueryExpr{
                           expr: unquote(expr),
                           params: unquote(params),
                           file: unquote(env.file),
                           line: unquote(env.line)}
    Builder.apply_query(query, __MODULE__, [group_by], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.t
  def apply(query, expr) do
    query = Ecto.Queryable.to_query(query)
    %{query | group_bys: query.group_bys ++ [expr]}
  end
end
