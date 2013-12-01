defmodule Ecto.Query.GroupByBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  @doc """
  Escapes a group by expression.

  A group by may be a variable, representing all fields in that
  entity, or a list of fields as `x.y`.

  ## Examples

      iex> escape(quote(do: [x.x, y.y]), [:x, :y])
      [{{:{}, [], [:&, [], [0]]}, :x},
       {{:{}, [], [:&, [], [1]]}, :y}]

      iex> escape(quote(do: x), [:x, :y])
      {:{}, [], [:&, [], [0]]}

  """
  @spec escape(Macro.t, [atom]) :: Macro.t | no_return
  def escape(list, vars) when is_list(list) do
    Enum.map(list, &escape_field(&1, vars))
  end

  def escape({ var, _, context }, vars) when is_atom(var) and is_atom(context) do
    BuilderUtil.escape_var(var, vars)
  end

  def escape(field, vars) do
    [escape_field(field, vars)]
  end

  defp escape_field(dot, vars) do
    case BuilderUtil.escape_dot(dot, vars) do
      { _, _ } = var_field ->
        var_field
      :error ->
        raise Ecto.QueryError, reason: "malformed `group_by` query expression"
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
    group_by = quote do: Ecto.Query.QueryExpr[expr: unquote(expr),
                           file: unquote(env.file), line: unquote(env.line)]
    BuilderUtil.apply_query(query, __MODULE__, [group_by], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.Query.t
  def apply(query, expr) do
    Ecto.Query.Query[group_bys: group_bys] = query = Ecto.Queryable.to_query(query)
    query.group_bys(group_bys ++ [expr])
  end
end
