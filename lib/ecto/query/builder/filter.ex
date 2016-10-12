import Kernel, except: [apply: 3]

defmodule Ecto.Query.Builder.Filter do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Escapes a where or having clause.

  It allows query expressions that evaluate to a boolean
  or a keyword list of field names and values. In a keyword
  list multiple key value pairs will be joined with "and".
  """
  @spec escape(:where | :having, :and | :or, Macro.t, Keyword.t, Macro.Env.t) :: {Macro.t, %{}}
  def escape(_kind, _op, [], _vars, _env) do
    {true, %{}}
  end

  def escape(kind, op, expr, vars, env) when is_list(expr) do
    {parts, params} =
      Enum.map_reduce(expr, %{}, fn
        {field, nil}, _acc ->
          Builder.error! "nil given for #{inspect field}. Comparison with nil is forbidden as it is unsafe. " <>
                         "Instead write a query with is_nil/1, for example: is_nil(s.#{field})"
        {field, value}, acc when is_atom(field) ->
          {value, params} = Builder.escape(value, {0, field}, acc, vars, env)
          {{:{}, [], [:==, [], [to_escaped_field(field), value]]}, params}
        _, _acc ->
          Builder.error! "expected a keyword list at compile time in #{kind}, " <>
                         "got: `#{Macro.to_string expr}`. If you would like to " <>
                         "pass a list dynamically, please interpolate the whole list with ^"
      end)

    expr = Enum.reduce parts, &{:{}, [], [op, [], [&2, &1]]}
    {expr, params}
  end

  def escape(_kind, _op, expr, vars, env) do
    Builder.escape(expr, :boolean, %{}, vars, env)
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(:where | :having, :and | :or, Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(kind, op, query, _binding, {:^, _, [var]}, env) do
    expr =
      quote do
        {expr, params} = Ecto.Query.Builder.Filter.runtime!(unquote(kind), unquote(var), unquote(op))
        %Ecto.Query.BooleanExpr{expr: expr, params: params, op: unquote(op),
                                file: unquote(env.file), line: unquote(env.line)}
      end
    Builder.apply_query(query, __MODULE__, [kind, expr], env)
  end

  def build(kind, op, query, binding, expr, env) do
    {query, binding} = Builder.escape_binding(query, binding)
    {expr, params} = escape(kind, op, expr, binding, env)
    params = Builder.escape_params(params)

    expr = quote do: %Ecto.Query.BooleanExpr{
                        expr: unquote(expr),
                        op: unquote(op),
                        params: unquote(params),
                        file: unquote(env.file),
                        line: unquote(env.line)}
    Builder.apply_query(query, __MODULE__, [kind, expr], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, :where | :having, term) :: Ecto.Query.t
  def apply(query, _, %{expr: true}) do
    query
  end
  def apply(%Ecto.Query{wheres: wheres} = query, :where, expr) do
    %{query | wheres: wheres ++ [expr]}
  end
  def apply(%Ecto.Query{havings: havings} = query, :having, expr) do
    %{query | havings: havings ++ [expr]}
  end
  def apply(query, kind, expr) do
    apply(Ecto.Queryable.to_query(query), kind, expr)
  end

  @doc """
  Invoked at runtime for interpolated lists.
  """
  def runtime!(_kind, [], _op) do
    {true, []}
  end

  def runtime!(kind, kw, op) when is_list(kw) do
    {parts, params} = runtime!(kw, 0, [], [], kind, kw)
    {Enum.reduce(parts, &{op, [], [&2, &1]}), params}
  end

  def runtime!(kind, other, _op) do
    raise ArgumentError, "expected a keyword list in `#{kind}`, got: `#{inspect other}`"
  end

  defp runtime!([{field, nil}|_], _counter, _exprs, _params, _kind, _original) when is_atom(field) do
    raise ArgumentError, "nil given for #{inspect field}. Comparison with nil is forbidden as it is unsafe. " <>
                         "Instead write a query with is_nil/1, for example: is_nil(s.#{field})"
  end

  defp runtime!([{field, value}|t], counter, exprs, params, kind, original) when is_atom(field) do
    runtime!(t, counter + 1,
             [{:==, [], [to_field(field), {:^, [], [counter]}]}|exprs],
             [{value, {0, field}}|params],
             kind, original)
  end

  defp runtime!([], _counter, exprs, params, _kind, _original) do
    {Enum.reverse(exprs), Enum.reverse(params)}
  end

  defp runtime!(_, _counter, _exprs, _params, kind, original) do
    raise ArgumentError, "expected a keyword list in `#{kind}`, got: `#{inspect original}`"
  end

  defp to_escaped_field(field), do: Macro.escape to_field(field)
  defp to_field(field), do: {{:., [], [{:&, [], [0]}, field]}, [], []}
end
