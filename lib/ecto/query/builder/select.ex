import Kernel, except: [apply: 2]

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

  """
  @spec escape(Macro.t, Keyword.t, Macro.Env.t) :: {Macro.t, {%{}, %{}}}
  def escape(other, vars, env) do
    if take?(other) do
      {{:{}, [], [:&, [], [0]]}, {%{}, %{0 => {:any, other}}}}
    else
      escape(other, {%{}, %{}}, vars, env)
    end
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
  defp escape({:%{}, _, [{:|, _, [data, pairs]}]}, params_take, vars, env) do
    {data, params_take} = escape(data, params_take, vars, env)
    {pairs, params_take} = escape_pairs(pairs, params_take, vars, env)
    {{:{}, [], [:%{}, [], [{:{}, [], [:|, [], [data, pairs]]}]]}, params_take}
  end

  defp escape({:%{}, _, pairs}, params_take, vars, env) do
    {pairs, params_take} = escape_pairs(pairs, params_take, vars, env)
    {{:{}, [], [:%{}, [], pairs]}, params_take}
  end

  # List
  defp escape(list, params_take, vars, env) when is_list(list) do
    Enum.map_reduce(list, params_take, &escape(&1, &2, vars, env))
  end

  # map/struct(var, [:foo, :bar])
  defp escape({tag, _, [{var, _, context}, fields]}, {params, take}, vars, env)
       when tag in [:map, :struct] and is_atom(var) and is_atom(context) do
    taken = escape_fields(fields, tag, env)
    expr  = Builder.escape_var(var, vars)
    take  = Map.put(take, Builder.find_var!(var, vars), {tag, taken})
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

  defp escape_pairs(pairs, params_take, vars, env) do
    Enum.map_reduce pairs, params_take, fn({k, v}, acc) ->
      {k, acc} = escape_key(k, acc, vars, env)
      {v, acc} = escape(v, acc, vars, env)
      {{k, v}, acc}
    end
  end

  defp escape_key(k, params_take, _vars, _env) when is_atom(k) do
    {k, params_take}
  end
  defp escape_key(k, params_take, vars, env) do
    escape(k, params_take, vars, env)
  end

  defp escape_fields({:^, _, [interpolated]}, tag, _env) do
    quote do
      Ecto.Query.Builder.Select.fields!(unquote(tag), unquote(interpolated))
    end
  end
  defp escape_fields(expr, tag, env) do
    case Macro.expand(expr, env) do
      fields when is_list(fields) ->
        fields
      _ ->
        Builder.error! "`#{tag}/2` in `select` expects either a literal or " <>
          "an interpolated list of atom fields"
    end
  end

  @doc """
  Called at runtime to verify a field.
  """
  def fields!(tag, fields) do
    if take?(fields) do
      fields
    else
      raise ArgumentError,
        "expected a list of fields in `#{tag}/2` inside `select`, got: `#{inspect fields}`"
    end
  end

  defp take?(fields) do
    is_list(fields) and Enum.all?(fields, fn
      {k, v} when is_atom(k) -> take?(List.wrap(v))
      k when is_atom(k) -> true
      _ -> false
    end)
  end

  @doc """
  Called at runtime for interpolated/dynamic selects.
  """
  def select!(query, fields, file, line) do
    take = %{0 => {:any, fields!(:select, fields)}}
    expr = %Ecto.Query.SelectExpr{expr: {:&, [], [0]}, take: take, file: file, line: line}
    apply(query, expr)
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t

  def build(query, _binding, {:^, _, [var]}, env) do
    quote do
      Ecto.Query.Builder.Select.select!(unquote(query), unquote(var),
                                        unquote(env.file), unquote(env.line))
    end
  end

  def build(query, binding, expr, env) do
    {query, binding} = Builder.escape_binding(query, binding)
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
  def apply(%Ecto.Query{select: nil} = query, expr) do
    %{query | select: expr}
  end
  def apply(%Ecto.Query{}, _expr) do
    Builder.error! "only one select expression is allowed in query"
  end
  def apply(query, expr) do
    apply(Ecto.Queryable.to_query(query), expr)
  end
end
