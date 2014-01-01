defmodule Ecto.Query.DistinctBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  @doc """
  Escapes a distinct expression.

  A distinct expression may be a single variable `x`, representing all fields in that
  entity, a field `x.y`, or a list of fields and variables.

  ## Examples

      iex> escape(quote(do: [x.x, y.y]), [:x, :y])
      [{{:{}, [], [:&, [], [0]]}, :x},
       {{:{}, [], [:&, [], [1]]}, :y}]

      iex> escape(quote(do: x), [:x, :y])
      [{:{}, [], [:&, [], [0]]}]

  """
  @spec escape(Macro.t, [atom]) :: Macro.t | no_return
  def escape(list, vars) when is_list(list) do
    Enum.map(list, &do_escape(&1, vars))
  end

  def escape(ast, vars) do
    [do_escape(ast, vars)]
  end

  defp do_escape({ var, _, context }, vars) when is_atom(var) and is_atom(context) do
    BuilderUtil.escape_var(var, vars)
  end

  defp do_escape(dot, vars) do
    case BuilderUtil.escape_dot(dot, vars) do
      { _, _ } = var_field ->
        var_field
      :error ->
        raise Ecto.QueryError, reason: "malformed `distinct` query expression"
    end
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
    distinct = quote do: Ecto.Query.QueryExpr[expr: unquote(expr),
                           file: unquote(env.file), line: unquote(env.line)]
    BuilderUtil.apply_query(query, __MODULE__, [distinct], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.Query.t
  def apply(query, expr) do
    Ecto.Query.Query[distincts: distincts] = query = Ecto.Queryable.to_query(query)
    query.distincts(distincts ++ [expr])
  end
end
