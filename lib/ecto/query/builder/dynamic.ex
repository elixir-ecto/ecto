import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.Dynamic do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Builds a dynamic expression.
  """
  @spec build([Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(binding, expr, env) do
    {query, vars} = Builder.escape_binding(quote(do: query), binding, env)
    {expr, {params, acc}} = Builder.escape(expr, :any, {[], %{subqueries: []}}, vars, env)
    params = Builder.escape_params(params)

    quote do
      %Ecto.Query.DynamicExpr{fun: fn query ->
                                _ = unquote(query)
                                {unquote(expr), unquote(params), unquote(acc.subqueries)}
                              end,
                              binding: unquote(Macro.escape(binding)),
                              file: unquote(env.file),
                              line: unquote(env.line)}
    end
  end

  @doc """
  Expands a dynamic expression for insertion into the given query.
  """
  def fully_expand(query, %{file: file, line: line, binding: binding} = dynamic) do
    {expr, {binding, params, subqueries, _count}} = expand(query, dynamic, {binding, [], [], 0})
    {expr, binding, Enum.reverse(params), Enum.reverse(subqueries), file, line}
  end

  @doc """
  Expands a dynamic expression as part of an existing expression.

  Any dynamic expression parameter is prepended and the parameters
  list is not reversed. This is useful when the dynamic expression
  is given in the middle of an expression.
  """
  def partially_expand(query, %{binding: binding} = dynamic, params, subqueries, count) do
    {expr, {_binding, params, subqueries, count}} =
      expand(query, dynamic, {binding, params, subqueries, count})

    {expr, params, subqueries, count}
  end

  def partially_expand(kind, query, %{binding: binding} = dynamic, params, count) do
    {expr, {_binding, params, subqueries, count}} =
      expand(query, dynamic, {binding, params, [], count})

    if subqueries != [] do
      raise ArgumentError, "subqueries are not allowed in `#{kind}` expressions"
    end

    {expr, params, count}
  end

  defp expand(query, %{fun: fun}, {binding, params, subqueries, count}) do
    {dynamic_expr, dynamic_params, dynamic_subqueries} = fun.(query)

    Macro.postwalk(dynamic_expr, {binding, params, subqueries, count}, fn
      {:^, meta, [ix]}, {binding, params, subqueries, count} ->
        case Enum.fetch!(dynamic_params, ix) do
          {%Ecto.Query.DynamicExpr{binding: new_binding} = dynamic, _} ->
            binding = if length(new_binding) > length(binding), do: new_binding, else: binding
            expand(query, dynamic, {binding, params, subqueries, count})

          param ->
            {{:^, meta, [count]}, {binding, [param | params], subqueries, count + 1}}
        end

      {:subquery, i}, {binding, params, subqueries, count} ->
        subquery = Enum.fetch!(dynamic_subqueries, i)
        ix = length(subqueries)
        {{:subquery, ix}, {binding, [{:subquery, ix} | params], [subquery | subqueries], count + 1}}

      expr, acc ->
        {expr, acc}
    end)
  end

  def expand_nested(struct, query) do
    case struct do
      %{expr: expr, params: params, subqueries: subqueries} ->
        acc = %{
          params: Enum.reverse(params),
          subqueries: Enum.reverse(subqueries),
          count: length(params)
        }

        {expr, %{params: params, subqueries: subqueries}} = expand_nested(expr, acc, query)
        %{struct | expr: expr, params: Enum.reverse(params), subqueries: Enum.reverse(subqueries)}

      %{expr: expr, params: params} ->
        acc = %{
          params: Enum.reverse(params),
          subqueries: [],
          count: length(params)
        }

        {expr, %{params: params}} = expand_nested(expr, acc, query)
        %{struct | expr: expr, params: Enum.reverse(params)}

      other ->
        other
    end
  end

  defp expand_nested(fields, acc, query) when is_map(fields) and not is_struct(fields) do
    {fields, acc} = expand_nested(Enum.to_list(fields), acc, query)
    {{:%{}, [], fields}, acc}
  end

  defp expand_nested(fields, acc, query) when is_list(fields) do
    Enum.map_reduce(fields, acc, &expand_nested(&1, &2, query))
  end

  defp expand_nested({key, val}, acc, query) do
    {val, acc} = expand_nested(val, acc, query)
    {{key, val}, acc}
  end

  defp expand_nested({name, meta, args}, acc, query) do
    {args, acc} = expand_nested(args, acc, query)
    {{name, meta, args}, acc}
  end

  defp expand_nested(%Ecto.Query.DynamicExpr{} = dynamic, acc, query) do
    {expr, params, subqueries, count} =
      partially_expand(query, dynamic, acc.params, acc.subqueries, acc.count)

    {expr, %{acc | params: params, subqueries: subqueries, count: count}}
  end

  defp expand_nested(other, acc, _query) do
    {other, acc}
  end
end
