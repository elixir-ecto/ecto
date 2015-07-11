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
    {expr, params} = Builder.escape(expr, :boolean, %{}, binding, env)
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
end
