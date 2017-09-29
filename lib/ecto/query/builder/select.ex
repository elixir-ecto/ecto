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

  # Struct
  defp escape({:%, _, [name, map]}, params_take, vars, env) do
    name = Macro.expand(name, env)
    {escaped_map, params_take} = escape(map, params_take, vars, env)
    {{:{}, [], [:%, [], [name, escaped_map]]}, params_take}
  end

  # Map
  defp escape({:%{}, _, [{:|, _, [data, pairs]}]}, params_take, vars, env) do
    {data, params_take} = escape(data, params_take, vars, env)
    {pairs, params_take} = escape_pairs(pairs, params_take, vars, env)
    {{:{}, [], [:%{}, [], [{:{}, [], [:|, [], [data, pairs]]}]]}, params_take}
  end

  # Merge
  defp escape({:merge, _, [left, right]}, params_take, vars, env) do
    {left, params_take} = escape(left, params_take, vars, env)
    {right, params_take} = escape(right, params_take, vars, env)
    {{:{}, [], [:merge, [], [left, right]]}, params_take}
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
    expr = Builder.escape_var(var, vars)
    take = merge_take(take, %{Builder.find_var!(var, vars) => {tag, taken}})
    {expr, {params, take}}
  end

  # var
  defp escape({var, _, context}, params_take, vars, _env)
      when is_atom(var) and is_atom(context) do
    expr = Builder.escape_var(var, vars)
    {expr, params_take}
  end

  defp escape({:type, _, [{{:., _, [{var, _, context}, field]}, _, []} = expr, type]},
              params_take, vars, env) when is_atom(var) and is_atom(context) and is_atom(field) do
    escape_with_type(expr, type, params_take, vars, env)
  end

  defp escape({:type, _, [{:fragment, _, [_ | _]} = expr, type]}, params_take, vars, env) do
    escape_with_type(expr, type, params_take, vars, env)
  end

  defp escape({:type, _, [{:unsafe_fragment, _, [_]} = expr, type]}, params_take, vars, env) do
    escape_with_type(expr, type, params_take, vars, env)
  end

  defp escape({:type, _, [{agg, _, [_ | _]} = expr, type]}, params_take, vars, env)
       when agg in ~w(avg count max min sum)a do
    escape_with_type(expr, type, params_take, vars, env)
  end

  defp escape(expr, params_take, vars, env) do
    Builder.escape(expr, :any, params_take, vars, {env, &escape_expansion/5})
  end

  defp escape_expansion(expr, _type, params_take, vars, env) do
    escape(expr, params_take, vars, env)
  end

  defp escape_with_type(expr, type, params_take, vars, env) do
    type = Builder.validate_type!(type, vars)
    {expr, params_take} =
      Builder.escape(expr, type, params_take, vars, {env, &escape_expansion/5})
    {{:{}, [], [:type, [], [expr, type]]}, params_take}
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
  def select!(kind, query, fields, file, line) do
    take = %{0 => {:any, fields!(:select, fields)}}
    expr = %Ecto.Query.SelectExpr{expr: {:&, [], [0]}, take: take, file: file, line: line}
    if kind == :select do
      apply(query, expr)
    else
      merge(query, expr)
    end
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(:select | :merge, Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t

  def build(kind, query, _binding, {:^, _, [var]}, env) do
    quote do
      Ecto.Query.Builder.Select.select!(unquote(kind), unquote(query), unquote(var),
                                        unquote(env.file), unquote(env.line))
    end
  end

  def build(kind, query, binding, expr, env) do
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

    if kind == :select do
      Builder.apply_query(query, __MODULE__, [select], env)
    else
      quote do
        Builder.Select.merge(unquote(query), unquote(select))
      end
    end
  end

  @doc """
  The callback applied by `build/5` to build the query.
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

  @doc """
  The callback applied by `build/5` when merging.
  """
  def merge(%Ecto.Query{select: nil} = query, new_select) do
    merge(query, new_select, {:&, [], [0]}, [], %{}, new_select)
  end
  def merge(%Ecto.Query{select: old_select} = query, new_select) do
    %{expr: old_expr, params: old_params, take: old_take} = old_select
    merge(query, old_select, old_expr, old_params, old_take, new_select)
  end
  def merge(query, expr) do
    merge(Ecto.Queryable.to_query(query), expr)
  end

  defp merge(query, select, old_expr, old_params, old_take, new_select) do
    %{expr: new_expr, params: new_params, take: new_take} = new_select

    expr =
      case {old_expr, new_expr} do
        {{:%{}, meta, old_fields}, {:%{}, _, new_fields}} when
            (old_fields == [] or tuple_size(hd(old_fields)) == 2) and
            (new_fields == [] or tuple_size(hd(new_fields)) == 2) and
            old_params == [] ->
          {:%{}, meta, Keyword.merge(old_fields, new_fields)}
        {{:%, meta, [name, {:%{}, meta, old_fields}]}, {:%{}, _, new_fields}} when
            (old_fields == [] or tuple_size(hd(old_fields)) == 2) and
            (new_fields == [] or tuple_size(hd(new_fields)) == 2) and
            old_params == [] ->
          {:%, meta, [name, {:%{}, meta, Keyword.merge(old_fields, new_fields)}]}
        {_, _} ->
          {:merge, [], [old_expr, new_expr]}
      end

    select = %{
      select | expr: expr,
               params: old_params ++ new_params,
               take: merge_take(old_take, new_take)
    }

    %{query | select: select}
  end

  defp merge_take(%{} = old_take, %{} = new_take) do
    Map.merge(old_take, new_take, &merge_take_kind_and_fields/3)
  end

  defp merge_take_kind_and_fields(binding, {old_kind, old_fields}, {new_kind, new_fields}) do
    {merge_take_kind(binding, old_kind, new_kind), Enum.uniq(old_fields ++ new_fields)}
  end

  defp merge_take_kind(_, kind, kind), do: kind
  defp merge_take_kind(_, :any, kind), do: kind
  defp merge_take_kind(_, kind, :any), do: kind
  defp merge_take_kind(binding, old, new) do
    Builder.error! "cannot apply select_merge because the binding at position #{binding} " <>
                   "was previously specified as a `#{old}` and later as `#{new}`"
  end
end
