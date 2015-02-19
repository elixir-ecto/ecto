defmodule Ecto.Query.Builder.Select do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Escapes a select.

  It allows tuples, lists and variables at the top level. Inside the
  tuples and lists query expressions are allowed.

  ## Examples

      iex> escape({1, 2}, [], __ENV__)
      {{:{}, [], [:{}, [], [1, 2]]}, %{}}

      iex> escape([1, 2], [], __ENV__)
      {[1, 2], %{}}

      iex> escape(quote(do: x), [x: 0], __ENV__)
      {{:{}, [], [:&, [], [0]]}, %{}}

      iex> escape(quote(do: ^123), [], __ENV__)
      {{:{}, [], [:^, [], [0]]}, %{0 => {123, :any}}}

  """
  @spec escape(Macro.t, Keyword.t, Macro.Env.t) :: {Macro.t, %{}}
  def escape(other, vars, env) do
    escape(other, %{}, vars, env)
  end

  # Tuple
  defp escape({left, right}, params, vars, env) do
    escape({:{}, [], [left, right]}, params, vars, env)
  end

  # Tuple
  defp escape({:{}, _, list}, params, vars, env) do
    {list, params} = Enum.map_reduce(list, params, &escape(&1, &2, vars, env))
    expr = {:{}, [], [:{}, [], list]}
    {expr, params}
  end

  # Map
  defp escape({:%{}, _, pairs}, params, vars, env) do
    {pairs, params} = Enum.map_reduce pairs, params, fn({k, v}, acc) ->
      unless is_atom(k) or is_binary(k) or is_number(k) do
				Builder.error! "keys can only be atoms/binaries/integers/floats"
      end
      {expr, params} = escape(v, acc, vars, env)
      {{k, expr}, params}
    end

    expr = {:{}, [], [:%{}, [], pairs]}
    {expr, params}
  end

  # List
  defp escape(list, params, vars, env) when is_list(list) do
    Enum.map_reduce(list, params, &escape(&1, &2, vars, env))
  end

  # var - where var is bound
  defp escape({var, _, context}, params, vars, _env)
      when is_atom(var) and is_atom(context) do
    expr = Builder.escape_var(var, vars)
    {expr, params}
  end

  defp escape(other, params, vars, env) do
    Builder.escape(other, :any, params, vars, env)
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(query, binding, expr, env) do
    binding        = Builder.escape_binding(binding)
    {expr, params} = escape(expr, binding, env)
    params         = Builder.escape_params(params)

    select = quote do: %Ecto.Query.SelectExpr{
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
