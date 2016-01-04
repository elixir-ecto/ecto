defmodule Ecto.Query.Builder.Select do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Escapes a select.

  It allows tuples, lists and variables at the top level. Inside the
  tuples and lists query expressions are allowed.

  ## Examples

      iex> escape({1, 2}, [], __ENV__)
      {{:{}, [], [:{}, [], [1, 2]]}, {%{}, %{}}}

      iex> escape([1, 2], [], __ENV__)
      {[1, 2], {%{}, %{}}}

      iex> escape(quote(do: x), [x: 0], __ENV__)
      {{:{}, [], [:&, [], [0]]}, {%{}, %{}}}

      iex> escape(quote(do: ^123), [], __ENV__)
      {{:{}, [], [:^, [], [0]]}, {%{0 => {123, :any}}, %{}}}

  """
  @spec escape(Macro.t, Keyword.t, Macro.Env.t) :: {Macro.t, %{}}
  def escape(other, vars, env) do
    escape(other, {%{}, %{}}, vars, env)
  end

  # Tuple
  defp escape({left, right}, params_take, vars, env) do
    escape({:{}, [], [left, right]}, params_take, vars, env)
  end

  # Tuple
  defp escape({:{}, _, list}, params_take, vars, env) do
    {list, params_take} = Enum.map_reduce(list, params_take, &escape(&1, &2, vars, env))
    expr = {:{}, [], [:{}, [], list]}
    {expr, params_take}
  end

  # Map
  defp escape({:%{}, _, pairs}, params_take, vars, env) do
    {pairs, params_take} = Enum.map_reduce pairs, params_take, fn({k, v}, acc) ->
      {k, acc} = escape_key(k, acc, vars, env)
      {v, acc} = escape(v, acc, vars, env)
      {{k, v}, acc}
    end

    expr = {:{}, [], [:%{}, [], pairs]}
    {expr, params_take}
  end

  # List
  defp escape(list, params_take, vars, env) when is_list(list) do
    Enum.map_reduce(list, params_take, &escape(&1, &2, vars, env))
  end

  # take(var, [:foo, :bar])
  defp escape({:take, _, [{var, _, context}, fields]}, {params, take}, vars, _env)
      when is_atom(var) and is_atom(context) do
    taken =
      case fields do
        {:^, _, [interpolated]} ->
          quote(do: Ecto.Query.Builder.Select.fields!(unquote(interpolated)))
        _ when is_list(fields) ->
          fields
        true ->
          Builder.error! "`take/2` in `select` expects either a literal or "
                         "an interpolated list of atom fields"
      end

    expr = Builder.escape_var(var, vars)
    take = Map.put(take, Builder.find_var!(var, vars), taken)
    {expr, {params, take}}
  end

  # var
  defp escape({var, _, context}, params_take, vars, _env)
      when is_atom(var) and is_atom(context) do
    expr = Builder.escape_var(var, vars)
    {expr, params_take}
  end

  defp escape(other, {params, take}, vars, env) do
    {other, params} = Builder.escape(other, :any, params, vars, env)
    {other, {params, take}}
  end

  defp escape_key(k, params_take, _vars, _env) when is_atom(k) do
    {k, params_take}
  end
  defp escape_key(k, params_take, vars, env) do
    escape(k, params_take, vars, env)
  end

  @doc """
  Called at runtime to verify a field.
  """
  def fields!(fields) when is_list(fields),
    do: fields
  def fields!(other) do
    raise ArgumentError,
      "expected a list of fields in `take/2` inside `select`, got: `#{inspect other}`"
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(query, binding, expr, env) do
    binding = Builder.escape_binding(binding)
    {expr, {params, take}} = escape(expr, binding, env)
    params = Builder.escape_params(params)
    take   = {:%{}, [], Map.to_list(take)}

    select = quote do: %Ecto.Query.SelectExpr{
                         expr: unquote(expr),
                         params: unquote(params),
                         file: unquote(env.file),
                         line: unquote(env.line),
                         take: unquote(take)}
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
