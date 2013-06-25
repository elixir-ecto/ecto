defmodule Ecto.Query.WhereBuilder do

  @unary_ops [ :not, :+, :- ]
  @binary_ops [ :==, :!=, :<=, :>=, :and, :or, :<, :>, :+, :-, :*, :/ ]

  defrecord State, external: [], binding: []

  def escape(ast) do
    { ast, vars } = escape(ast, State[])
    { ast, vars.update_external(Enum.uniq(&1)).update_binding(Enum.uniq(&1)) }
  end

  defp escape({ { :., _, [{ var, _, context}, _right] } = dot, meta, [] }, vars)
       when is_atom(var) and is_atom(context) do
    { dot_ast, _ } = escape(dot, vars)
    vars = update_vars(vars, [{var, context}])
    { { :"{}", [], [dot_ast, meta, []] }, vars }
  end

  defp escape({ { :., _, [_, _] }, _, args } = ast, vars) when is_list(args) do
    { ast, vars.update_external(get_vars(ast) ++ &1) }
  end

  defp escape({ :., meta, [{ var, meta2, context } = left, right] }, vars)
      when is_atom(var) and is_atom(context) do
    vars = update_vars(vars, get_vars(left))
    left = { :"{}", [], [var, meta2, context] }
    { { :"{}", [], [:., meta, [left, right]] }, vars }
  end

  defp escape({ var, _, context } = ast, vars) when is_atom(var) and is_atom(context) do
    { ast, vars.update_external(get_vars(ast) ++ &1) }
  end

  defp escape({ op, meta, [arg] }, vars) when op in @unary_ops do
    { arg_ast, vars } = escape(arg, vars)
    { { :"{}", [], [op, meta, [arg_ast]] }, vars }
  end

  defp escape({ op, meta, [left, right] }, vars) when op in @binary_ops do
    { left_ast, vars } = escape(left, vars)
    { right_ast, vars } = escape(right, vars)
    { { :"{}", [], [op, meta, [left_ast, right_ast]] }, vars }
  end

  defp escape({ fun, _, args } = ast, vars) when is_atom(fun) and is_list(args) do
    { ast, vars.update_external(get_vars(ast) ++ &1) }
  end

  defp escape({ left, meta, right }, vars) do
    { left_ast, vars } = escape(left, vars)
    { right_ast, vars } = escape(right, vars)
    { { :"{}", [], [left_ast, meta, right_ast] }, vars }
  end

  defp escape({ left, right }, vars) do
    { left_ast, vars } = escape(left, vars)
    { right_ast, vars } = escape(right, vars)
    { { left_ast, right_ast }, vars }
  end

  defp escape(list, vars) when is_list(list) do
    Enum.map_reduce(list, vars, escape(&1, &2))
  end

  defp escape(other, vars) do
    { other, vars }
  end


  defp get_vars(ast), do: get_vars(ast, [])

  defp get_vars({ var, _, context }, acc) when is_atom(var) and is_atom(context) do
    [{ var, context }|acc]
  end

  defp get_vars({ left, _, right }, acc) do
    get_vars(right, get_vars(left, acc))
  end

  defp get_vars({ left, right }, acc) do
    get_vars(right, get_vars(left, acc))
  end

  defp get_vars(list, acc) when is_list(list) do
    Enum.reduce list, acc, get_vars(&1, &2)
  end

  defp get_vars(_, acc), do: acc


  defp validate(_ast) do
  end


  defp update_vars(State[external: external, binding: binding], vars) do
    State[external: vars ++ external, binding: vars ++ binding]
  end
end
