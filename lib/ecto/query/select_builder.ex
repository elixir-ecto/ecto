defmodule Ecto.Query.SelectBuilder do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Escapes a select.

  It allows tuples, lists and variables at the top level or a
  single `assoc(x, y)` expression.

  ## Examples

      iex> escape({1, 2}, [])
      {{:{}, [], [:{}, [], [1, 2]]}, %{}}

      iex> escape([1, 2], [])
      {[1, 2], %{}}

      iex> escape(quote(do: x), [x: 0])
      {{:{}, [], [:&, [], [0]]}, %{}}

      iex> escape(quote(do: ^123), [])
      {{:{}, [], [:^, [], [0]]}, %{0 => 123}}

  """
  @spec escape(Macro.t, Keyword.t) :: {Macro.t, %{}}
  def escape({:assoc, _, args} = assoc, vars) when is_list(args) do
    escape_assoc(assoc, %{}, vars)
  end

  def escape(other, vars), do: do_escape(other, %{}, vars)

  # Tuple
  defp do_escape({left, right}, external, vars) do
    do_escape({:{}, [], [left, right]}, external, vars)
  end

  # Tuple
  defp do_escape({:{}, _, list}, external, vars) do
    {list, external} = Enum.map_reduce(list, external, &do_escape(&1, &2, vars))
    expr = {:{}, [], [:{}, [], list]}
    {expr, external}
  end

  # List
  defp do_escape(list, external, vars) when is_list(list) do
    Enum.map_reduce(list, external, &do_escape(&1, &2, vars))
  end

  # var - where var is bound
  defp do_escape({var, _, context}, external, vars)
      when is_atom(var) and is_atom(context) do
    expr = Builder.escape_var(var, vars)
    {expr, external}
  end

  defp do_escape(other, external, vars) do
    Builder.escape(other, external, vars)
  end

  # assoc/2
  defp escape_assoc({:assoc, _, [{var, _, context}, list]}, external, vars)
      when is_atom(var) and is_atom(context) and is_list(list) do
    var = Builder.escape_var(var, vars)
    {list, external} = Enum.map_reduce(list, external,
                                       &escape_assoc_fields(&1, &2, vars))

    expr = {:{}, [], [:assoc, [], [var, list]]}
    {expr, external}
  end

  defp escape_assoc(other, _external, _vars) do
    raise Ecto.QueryError,
      reason: "`#{Macro.to_string(other)}` is not a valid expression inside `assoc/2` selector"
  end

  defp escape_assoc_fields({field, {assoc_var, _, assoc_ctxt}}, external, vars)
      when is_atom(field) and is_atom(assoc_var) and is_atom(assoc_ctxt) do
    expr = {field, Builder.escape_var(assoc_var, vars)}
    {expr, external}
  end

  defp escape_assoc_fields({field, other}, external, vars)
      when is_atom(field) do
    {expr, external} = escape_assoc(other, external, vars)
    {{field, expr}, external}
  end

  defp escape_assoc_fields(other, external, vars) do
    escape_assoc(other, external, vars)
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(query, binding, expr, env) do
    binding          = Builder.escape_binding(binding)
    {expr, external} = escape(expr, binding)
    external         = Builder.escape_external(external)

    select = quote do: %Ecto.Query.QueryExpr{
                         expr: unquote(expr),
                         external: unquote(external),
                         file: unquote(env.file),
                         line: unquote(env.line)}
    Builder.apply_query(query, __MODULE__, [select], env)
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
