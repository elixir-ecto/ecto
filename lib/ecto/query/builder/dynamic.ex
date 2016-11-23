import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.Dynamic do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Builds a dynamic expression.
  """
  @spec build([Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(binding, expr, env) do
    {query, vars} = Builder.escape_binding(quote(do: query), binding)
    {expr, params} = Builder.escape(expr, :any, %{}, vars, env)
    params = Builder.escape_params(params)

    quote do
      %Ecto.Query.DynamicExpr{fun: fn query ->
                                _ = unquote(query)
                                {unquote(expr), unquote(params)}
                              end,
                              binding: unquote(Macro.escape(binding)),
                              file: unquote(env.file),
                              line: unquote(env.line)}
    end
  end

  @doc """
  Expands a dynamic expression for insertion into the given query.
  """
  def fully_expand(query, %{file: file, line: line} = dynamic) do
    {expr, params} = partially_expand(query, dynamic, [])
    {expr, Enum.reverse(params), file, line}
  end

  @doc """
  Expands a dynamic expression as part of an existing expression.

  Any dynamic expression parameter is prepended and the parameters
  list is not reversed. This is useful when the dynamic expression
  is given in the middle of an expression.
  """
  def partially_expand(query, %{fun: fun}, params) do
    {dynamic_expr, dynamic_params} =
      fun.(query)

    {params, dynamic, rewrite} =
      params_map(dynamic_params, params, %{}, %{}, 0, length(params))

    Macro.postwalk(dynamic_expr, params, fn
      {:^, meta, [ix]}, acc ->
        cond do
          dynamic = dynamic[ix] ->
            partially_expand(query, dynamic, acc)
          rewrite = rewrite[ix] ->
            {{:^, meta, [rewrite]}, acc}
        end
      expr, acc ->
        {expr, acc}
    end)
  end

  defp params_map([{%Ecto.Query.DynamicExpr{} = expr, _} | rest],
                  params, dynamic, rewrite, count, offset) do
    dynamic = Map.put(dynamic, count, expr)
    params_map(rest, params, dynamic, rewrite, count + 1, offset - 1)
  end

  defp params_map([param | rest], params, dynamic, rewrite, count, offset) do
    rewrite = Map.put(rewrite, count, count + offset)
    params_map(rest, [param | params], dynamic, rewrite, count + 1, offset)
  end

  defp params_map([], params, dynamic, rewrite, _count, _offset) do
    {params, dynamic, rewrite}
  end
end
