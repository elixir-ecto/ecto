defmodule Ecto.Query.Builder.Filter do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(:where | :having, Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(kind, query, binding, expr, env) do
    binding        = Builder.escape_binding(binding)
    {expr, params} = escape(expr, binding, env)
    params         = Builder.escape_params(params)

    expr = quote do: %Ecto.Query.QueryExpr{
                        expr: unquote(expr),
                        params: unquote(params),
                        file: unquote(env.file),
                        line: unquote(env.line)}
    Builder.apply_query(query, __MODULE__, [kind, expr], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, :where | :having, term) :: Ecto.Query.t
  def apply(query, :where, expr) do
    query = Ecto.Queryable.to_query(query)
    %{query | wheres: query.wheres ++ [expr]}
  end

  def apply(query, :having, expr) do
    query = Ecto.Queryable.to_query(query)
    %{query | havings: query.havings ++ [expr]}
  end

  @doc """
  Escapes a where or having clause.

  It allows query expressions that evaluate to a boolean
  or a keyword list of field names and values. In a keyword
  list multiple key value pairs will be joined with "and".
  """
  @spec escape(Macro.t, Keyword.t, Macro.Env.t) :: {Macro.t, %{}}
  def escape([], vars, env) do
    {[], %{}}
  end

  def escape(expr, vars, env) when is_list(expr) do
    {parts, params} =
      Enum.map_reduce(expr, %{}, fn {field, value}, acc ->
        {value, params} = Builder.escape(value, {0, field}, acc, vars, env)
        {[:==, [], [to_field(field), value]], params}
      end)

    expr = Enum.reduce parts, &[:and, [], [{:{}, [], &1}, {:{}, [], &2}]]
    {{:{}, [], expr}, params}
  end

  def escape(expr, vars, env) do
    Builder.escape(expr, :boolean, %{}, vars, env)
  end

  defp to_field(field), do: Macro.escape {{:., [], [{:&, [], [0]}, field]}, [], []}
end
