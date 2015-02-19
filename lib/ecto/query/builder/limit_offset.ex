defmodule Ecto.Query.Builder.LimitOffset do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(:limit | :offset, Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(type, query, binding, expr, env) do
    binding        = Builder.escape_binding(binding)
    {expr, params} = Builder.escape(expr, :integer, %{}, binding, env)
    params         = Builder.escape_params(params)

    if contains_variable?(expr) do
      Builder.error! "query variables are not allowed in #{type} expression"
    end

    limoff = quote do: %Ecto.Query.QueryExpr{
                        expr: unquote(expr),
                        params: unquote(params),
                        file: unquote(env.file),
                        line: unquote(env.line)}

    Builder.apply_query(query, __MODULE__, [type, limoff], env)
  end

  defp contains_variable?({:&, _, _}),
    do: true
  defp contains_variable?({left, _, right}),
    do: contains_variable?(left) or contains_variable?(right)
  defp contains_variable?({left, right}),
    do: contains_variable?(left) or contains_variable?(right)
  defp contains_variable?(list) when is_list(list),
    do: Enum.any?(list, &contains_variable?/1)
  defp contains_variable?(_),
    do: false

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, :limit | :offset, term) :: Ecto.Query.t
  def apply(query, :limit, expr) do
    query = Ecto.Queryable.to_query(query)
    %{query | limit: expr}
  end

  def apply(query, :offset, expr) do
    query = Ecto.Queryable.to_query(query)
    %{query | offset: expr}
  end
end
