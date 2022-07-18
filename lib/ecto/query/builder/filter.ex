import Kernel, except: [apply: 3]

defmodule Ecto.Query.Builder.Filter do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Escapes a where or having clause.

  It allows query expressions that evaluate to a boolean
  or a keyword list of field names and values. In a keyword
  list multiple key value pairs will be joined with "and".

  Returned is `{expression, {params, subqueries}}` which is
  a valid escaped expression, see `Macro.escape/2`. Both params
  and subqueries are reversed.
  """
  @spec escape(:where | :having | :on, Macro.t, non_neg_integer, Keyword.t, Macro.Env.t) :: {Macro.t, {list, list}}
  def escape(_kind, [], _binding, _vars, _env) do
    {true, {[], %{subqueries: []}}}
  end

  def escape(kind, expr, binding, vars, env) when is_list(expr) do
    {parts, params_acc} =
      Enum.map_reduce(expr, {[], %{subqueries: []}}, fn
        {field, nil}, _params_acc ->
          Builder.error! "nil given for `#{field}`. Comparison with nil is forbidden as it is unsafe. " <>
                         "Instead write a query with is_nil/1, for example: is_nil(s.#{field})"

        {field, value}, params_acc when is_atom(field) ->
          value = check_for_nils(value, field)
          {value, params_acc} = Builder.escape(value, {binding, field}, params_acc, vars, env)
          {{:{}, [], [:==, [], [to_escaped_field(binding, field), value]]}, params_acc}

        _, _params_acc ->
          Builder.error! "expected a keyword list at compile time in #{kind}, " <>
                         "got: `#{Macro.to_string expr}`. If you would like to " <>
                         "pass a list dynamically, please interpolate the whole list with ^"
      end)

    expr = Enum.reduce parts, &{:{}, [], [:and, [], [&2, &1]]}
    {expr, params_acc}
  end

  def escape(_kind, expr, _binding, vars, env) do
    Builder.escape(expr, :boolean, {[], %{subqueries: []}}, vars, env)
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(:where | :having, :and | :or, Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(kind, op, query, _binding, {:^, _, [var]}, env) do
    quote do
      Ecto.Query.Builder.Filter.filter!(unquote(kind), unquote(op), unquote(query),
                                        unquote(var), 0, unquote(env.file), unquote(env.line))
    end
  end

  def build(kind, op, query, binding, expr, env) do
    {query, binding} = Builder.escape_binding(query, binding, env)
    {expr, {params, acc}} = escape(kind, expr, 0, binding, env)

    params = Builder.escape_params(params)
    subqueries = Enum.reverse(acc.subqueries)

    expr = quote do: %Ecto.Query.BooleanExpr{
                        expr: unquote(expr),
                        op: unquote(op),
                        params: unquote(params),
                        subqueries: unquote(subqueries),
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
  Builds a filter based on the given arguments.

  This is shared by having, where and join's on expressions.
  """
  def filter!(kind, query, %Ecto.Query.DynamicExpr{} = dynamic, _binding, _file, _line) do
    {expr, _binding, params, subqueries, file, line} =
      Ecto.Query.Builder.Dynamic.fully_expand(query, dynamic)

    if subqueries != [] do
      raise ArgumentError, "subqueries are not allowed in `#{kind}` expressions"
    end

    {expr, params, file, line}
  end

  def filter!(_kind, _query, bool, _binding, file, line) when is_boolean(bool) do
    {bool, [], file, line}
  end

  def filter!(kind, _query, kw, binding, file, line) when is_list(kw) do
    {expr, params} = kw!(kind, kw, binding)
    {expr, params, file, line}
  end

  def filter!(kind, _query, other, _binding, _file, _line) do
    raise ArgumentError, "expected a keyword list or dynamic expression in `#{kind}`, got: `#{inspect other}`"
  end

  @doc """
  Builds the filter and applies it to the given query as boolean operator.
  """
  def filter!(:where, op, query, %Ecto.Query.DynamicExpr{} = dynamic, _binding, _file, _line) do
    {expr, _binding, params, subqueries, file, line} =
      Ecto.Query.Builder.Dynamic.fully_expand(query, dynamic)

    boolean = %Ecto.Query.BooleanExpr{
      expr: expr,
      params: params,
      line: line,
      file: file,
      op: op,
      subqueries: subqueries
    }

    apply(query, :where, boolean)
  end

  def filter!(kind, op, query, expr, binding, file, line) do
    {expr, params, file, line} = filter!(kind, query, expr, binding, file, line)
    boolean = %Ecto.Query.BooleanExpr{expr: expr, params: params, line: line, file: file, op: op}
    apply(query, kind, boolean)
  end

  defp kw!(kind, kw, binding) do
    case kw!(kw, binding, 0, [], [], kind, kw) do
      {[], params} -> {true, params}
      {parts, params} -> {Enum.reduce(parts, &{:and, [], [&2, &1]}), params}
    end
  end

  defp kw!([{field, nil}|_], _binding, _counter, _exprs, _params, _kind, _original) when is_atom(field) do
    raise ArgumentError, "nil given for #{inspect field}. Comparison with nil is forbidden as it is unsafe. " <>
                         "Instead write a query with is_nil/1, for example: is_nil(s.#{field})"
  end
  defp kw!([{field, value}|t], binding, counter, exprs, params, kind, original) when is_atom(field) do
    kw!(t, binding, counter + 1,
        [{:==, [], [to_field(binding, field), {:^, [], [counter]}]}|exprs],
        [{value, {binding, field}}|params],
        kind, original)
  end
  defp kw!([], _binding, _counter, exprs, params, _kind, _original) do
    {Enum.reverse(exprs), Enum.reverse(params)}
  end
  defp kw!(_, _binding, _counter, _exprs, _params, kind, original) do
    raise ArgumentError, "expected a keyword list in `#{kind}`, got: `#{inspect original}`"
  end

  defp to_field(binding, field),
    do: {{:., [], [{:&, [], [binding]}, field]}, [], []}
  defp to_escaped_field(binding, field),
    do: {:{}, [], [{:{}, [], [:., [], [{:{}, [], [:&, [], [binding]]}, field]]}, [], []]}

  defp check_for_nils({:^, _, [var]}, field) do
    quote do
      ^Ecto.Query.Builder.Filter.not_nil!(unquote(var), unquote(field))
    end
  end

  defp check_for_nils(value, _field), do: value

  def not_nil!(nil, field) do
    raise ArgumentError, "nil given for `#{field}`. comparison with nil is forbidden as it is unsafe. " <>
                           "Instead write a query with is_nil/1, for example: is_nil(s.#{field})"
  end

  def not_nil!(other, _field), do: other
end
