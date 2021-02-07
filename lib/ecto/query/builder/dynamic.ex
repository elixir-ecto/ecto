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
    {expr, {params, subqueries}} = Builder.escape(expr, :any, {[], []}, vars, env)
    params = Builder.escape_params(params)

    quote do
      %Ecto.Query.DynamicExpr{fun: fn query ->
                                _ = unquote(query)
                                {unquote(expr), unquote(params), unquote(subqueries)}
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
  def partially_expand(kind, query, %{binding: binding} = dynamic, params, count) do
    {expr, {_binding, params, subqueries, count}} = expand(query, dynamic, {binding, params, [], count})

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
end
