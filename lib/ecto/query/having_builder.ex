defmodule Ecto.Query.HavingBuilder do
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
    binding = BuilderUtil.escape_binding(binding)
    expr    = BuilderUtil.escape(expr, binding)
    having  = quote do: %Ecto.Query.QueryExpr{expr: unquote(expr),
                        file: unquote(env.file), line: unquote(env.line)}
    BuilderUtil.apply_query(query, __MODULE__, [having], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.t
  def apply(query, expr) do
    query = Ecto.Queryable.to_query(query)
    %{query | havings: query.havings ++ [expr]}
  end
end
