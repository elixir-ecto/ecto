defmodule Ecto.Query.WhereBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(query, binding, expr, env) do
    binding          = BuilderUtil.escape_binding(binding)
    {expr, external} = BuilderUtil.escape(expr, binding)
    external         = BuilderUtil.escape_external(external)

    where = quote do: %Ecto.Query.QueryExpr{
                        expr: unquote(expr),
                        external: unquote(external),
                        file: unquote(env.file),
                        line: unquote(env.line)}
    BuilderUtil.apply_query(query, __MODULE__, [where], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.t
  def apply(query, expr) do
    query = Ecto.Queryable.to_query(query)
    %{query | wheres: query.wheres ++ [expr]}
  end
end
