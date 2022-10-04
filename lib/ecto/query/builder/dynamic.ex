import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.Dynamic do
  @moduledoc false

  alias Ecto.Query.Builder
  alias Ecto.Query.Builder.Select

  @doc """
  Builds a dynamic expression.
  """
  @spec build([Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(binding, expr, env) do
    {query, vars} = Builder.escape_binding(quote(do: query), binding, env)
    {expr, {params, acc}} = escape(expr, {[], %{subqueries: [], aliases: %{}}}, vars, env)
    aliases = Builder.escape_select_aliases(acc.aliases)
    params = Builder.escape_params(params)

    quote do
      %Ecto.Query.DynamicExpr{fun: fn query ->
                                _ = unquote(query)
                                {unquote(expr), unquote(params), unquote(Enum.reverse(acc.subqueries)), unquote(aliases)}
                              end,
                              binding: unquote(Macro.escape(binding)),
                              file: unquote(env.file),
                              line: unquote(env.line)}
    end
  end

  defp escape({:selected_as, _, [_, _]} = expr, _params_acc, vars, env) do
    Select.escape(expr, vars, env)
  end

  defp escape(expr, params_acc, vars, env) do
    Builder.escape(expr, :any, params_acc, vars, {env, &escape_expansion/5})
  end

  defp escape_expansion(expr, _type, params_acc, vars, env) do
    escape(expr, params_acc, vars, env)
  end

  @doc """
  Expands a dynamic expression for insertion into the given query.
  """
  def fully_expand(query, %{file: file, line: line, binding: binding} = dynamic) do
    {expr, {binding, params, subqueries, _aliases, _count}} = expand(query, dynamic, {binding, [], [], %{}, 0})
    {expr, binding, Enum.reverse(params), Enum.reverse(subqueries), file, line}
  end

  @doc """
  Expands a dynamic expression as part of an existing expression.

  Any dynamic expression parameter is prepended and the parameters
  list is not reversed. This is useful when the dynamic expression
  is given in the middle of an expression.
  """
  def partially_expand(query, %{binding: binding} = dynamic, params, subqueries, aliases, count) do
    {expr, {_binding, params, subqueries, aliases, count}} =
      expand(query, dynamic, {binding, params, subqueries, aliases, count})

    {expr, params, subqueries, aliases, count}
  end

  def partially_expand(kind, query, %{binding: binding} = dynamic, params, count) do
    {expr, {_binding, params, subqueries, _aliases, count}} =
      expand(query, dynamic, {binding, params, [], %{}, count})

    if subqueries != [] do
      raise ArgumentError, "subqueries are not allowed in `#{kind}` expressions"
    end

    {expr, params, count}
  end

  defp expand(query, %{fun: fun}, {binding, params, subqueries, aliases, count}) do
    {dynamic_expr, dynamic_params, dynamic_subqueries, dynamic_aliases} = fun.(query)
    aliases = merge_aliases(aliases, dynamic_aliases)

    Macro.postwalk(dynamic_expr, {binding, params, subqueries, aliases, count}, fn
      {:^, meta, [ix]}, {binding, params, subqueries, aliases, count} ->
        case Enum.fetch!(dynamic_params, ix) do
          {%Ecto.Query.DynamicExpr{binding: new_binding} = dynamic, _} ->
            binding = if length(new_binding) > length(binding), do: new_binding, else: binding
            expand(query, dynamic, {binding, params, subqueries, aliases, count})

          param ->
            {{:^, meta, [count]}, {binding, [param | params], subqueries, aliases, count + 1}}
        end

      {:subquery, i}, {binding, params, subqueries, aliases, count} ->
        subquery = Enum.fetch!(dynamic_subqueries, i)
        ix = length(subqueries)
        {{:subquery, ix}, {binding, [{:subquery, ix} | params], [subquery | subqueries], aliases, count + 1}}

      expr, acc ->
        {expr, acc}
    end)
  end

  defp merge_aliases(old_aliases, new_aliases) do
    Enum.reduce(new_aliases, old_aliases, fn {alias, _}, aliases ->
      Builder.add_select_alias(aliases, alias)
    end)
  end
end
