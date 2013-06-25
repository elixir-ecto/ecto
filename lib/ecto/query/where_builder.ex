defmodule Ecto.Query.WhereBuilder do

  @unary_ops [ :not, :+, :- ]
  @binary_ops [ :==, :!=, :<=, :>=, :and, :or, :<, :>, :+, :-, :*, :/ ]

  defrecord State, external: [], binding: []

  def escape(ast) do
    { ast, vars } = escape(ast, State[])
    { ast, vars.update_external(Enum.uniq(&1)).update_binding(Enum.uniq(&1)) }
  end

  # var.x - dotted function call with no args where left side is var
  defp escape({ { :., _, [{ var, _, context}, _right] } = dot, meta, [] }, state)
       when is_atom(var) and is_atom(context) do
    { dot_ast, _ } = escape(dot, state)
    state = update_vars(state, [{var, context}])
    { { :{}, [], [dot_ast, meta, []] }, state }
  end

  # anything dotted that isnt a function call
  defp escape({ :., meta, [{ var, meta2, context } = left, right] }, state)
      when is_atom(var) and is_atom(context) do
    state = update_vars(state, get_vars(left, []))
    left = { :{}, [], [var, meta2, context] }
    { { :{}, [], [:., meta, [left, right]] }, state }
  end

  # unary op
  defp escape({ op, meta, [arg] }, state) when op in @unary_ops do
    { arg_ast, state } = escape(arg, state)
    { { :{}, [], [op, meta, [arg_ast]] }, state }
  end

  # binary op
  defp escape({ op, meta, [left, right] }, state) when op in @binary_ops do
    { left_ast, state } = escape(left, state)
    { right_ast, state } = escape(right, state)
    { { :{}, [], [op, meta, [left_ast, right_ast]] }, state }
  end

  # everything else is unknown
  defp escape(other, state) do
    { other, state.update_external(get_vars(other, &1)) }
  end

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
