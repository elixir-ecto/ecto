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
    binding = BuilderUtil.escape_binding(binding)
    expr    = BuilderUtil.escape(expr, binding)
    where   = Ecto.Query.QueryExpr[expr: expr, file: env.file, line: env.line]
    BuilderUtil.apply_query(query, __MODULE__, [where], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.Query.t
  def apply(query, expr) do
    Ecto.Query.Query[wheres: wheres] = query = Ecto.Queryable.to_query(query)
    query.wheres(wheres ++ [expr])
  end
end
