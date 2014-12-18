defmodule Ecto.Query.Builder.Select do
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
  defp do_escape({left, right}, params, vars) do
    do_escape({:{}, [], [left, right]}, params, vars)
  end

  # Tuple
  defp do_escape({:{}, _, list}, params, vars) do
    {list, params} = Enum.map_reduce(list, params, &do_escape(&1, &2, vars))
    expr = {:{}, [], [:{}, [], list]}
    {expr, params}
  end

  # List
  defp do_escape(list, params, vars) when is_list(list) do
    Enum.map_reduce(list, params, &do_escape(&1, &2, vars))
  end

  # var - where var is bound
  defp do_escape({var, _, context}, params, vars)
      when is_atom(var) and is_atom(context) do
    expr = Builder.escape_var(var, vars)
    {expr, params}
  end

  defp do_escape(other, params, vars) do
    Builder.escape(other, :any, params, vars)
  end

  # assoc/2
  defp escape_assoc({:assoc, _, [{var, _, context}, list]}, params, vars)
      when is_atom(var) and is_atom(context) and is_list(list) do
    var = Builder.escape_var(var, vars)
    {list, params} = Enum.map_reduce(list, params,
                                       &escape_assoc_fields(&1, &2, vars))

    expr = {:{}, [], [:assoc, [], [var, list]]}
    {expr, params}
  end

  defp escape_assoc(other, _params, _vars) do
    Builder.error! "invalid expression `#{Macro.to_string(other)}` inside `assoc/2` selector"
  end

  defp escape_assoc_fields({field, {assoc_var, _, assoc_ctxt}}, params, vars)
      when is_atom(field) and is_atom(assoc_var) and is_atom(assoc_ctxt) do
    expr = {field, Builder.escape_var(assoc_var, vars)}
    {expr, params}
  end

  defp escape_assoc_fields({field, other}, params, vars)
      when is_atom(field) do
    {expr, params} = escape_assoc(other, params, vars)
    {{field, expr}, params}
  end

  defp escape_assoc_fields(other, params, vars) do
    escape_assoc(other, params, vars)
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
    {expr, params} = escape(expr, binding)
    params         = Builder.escape_params(params)

    select = quote do: %Ecto.Query.QueryExpr{
                         expr: unquote(expr),
                         params: unquote(params),
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
      Builder.error! "only one select expression is allowed in query"
    else
      %{query | select: select}
    end
  end
end
