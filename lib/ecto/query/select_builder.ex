defmodule Ecto.Query.SelectBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  @doc """
  Escapes a select.

  It allows tuples, lists and variables at the top level or a
  single `assoc(x, y)` expression.

  ## Examples

      iex> escape({1, 2}, [])
      {:{}, [], [ :{}, [], [1, 2] ]}

      iex> escape([ 1, 2 ], [])
      [1, 2]

      iex> escape(quote(do: x), [x: 0])
      {:{}, [], [:&, [], [0]]}

  """
  @spec escape(Macro.t, Keyword.t) :: Macro.t
  def escape({:assoc, _, args} = assoc, vars) when is_list(args) do
    escape_assoc(assoc, vars)
  end

  def escape(other, vars), do: do_escape(other, vars)

  # Tuple
  defp do_escape({left, right}, vars) do
    do_escape({:{}, [], [left, right]}, vars)
  end

  # Tuple
  defp do_escape({:{}, _, list}, vars) do
    list = Enum.map(list, &do_escape(&1, vars))
    {:{}, [], [:{}, [], list]}
  end

  # List
  defp do_escape(list, vars) when is_list(list) do
    Enum.map(list, &do_escape(&1, vars))
  end

  # var - where var is bound
  defp do_escape({var, _, context}, vars) when is_atom(var) and is_atom(context) do
    BuilderUtil.escape_var(var, vars)
  end

  defp do_escape(other, vars) do
    BuilderUtil.escape(other, vars)
  end

  # assoc/2
  defp escape_assoc({:assoc, _, [{var, _, context}, list]}, vars)
      when is_atom(var) and is_atom(context) and is_list(list) do
    var = BuilderUtil.escape_var(var, vars)

    list = Enum.map(list, fn
      {field, {assoc_var, _, assoc_ctxt}}
          when is_atom(field) and is_atom(assoc_var) and is_atom(assoc_ctxt) ->
        {field, BuilderUtil.escape_var(assoc_var, vars)}

      {field, other} when is_atom(field) ->
        {field, escape_assoc(other, vars)}

      other ->
        escape_assoc(other, vars)
    end)

    {:{}, [], [:assoc, [], [var, list]]}
  end

  defp escape_assoc(other, _vars) do
    raise Ecto.QueryError,
      reason: "`#{Macro.to_string(other)}` is not a valid expression inside `assoc/2` selector"
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(query, binding, expr, env) do
    binding = BuilderUtil.escape_binding(binding)
    expr    = escape(expr, binding)
    select  = quote do: %Ecto.Query.QueryExpr{expr: unquote(expr),
                          file: unquote(env.file), line: unquote(env.line)}
    BuilderUtil.apply_query(query, __MODULE__, [select], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.t
  def apply(query, select) do
    query = Ecto.Queryable.to_query(query)

    if query.select do
      raise Ecto.QueryError, reason: "only one select expression is allowed in query"
    else
      %{query | select: select}
    end
  end
end
