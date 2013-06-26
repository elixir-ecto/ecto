defmodule Ecto.Query.WhereBuilder do
  @moduledoc false

  @unary_ops [ :not, :+, :- ]
  @binary_ops [ :==, :!=, :<=, :>=, :and, :or, :<, :>, :+, :-, :*, :/ ]

  # var.x - where var is bound
  def escape({ { :., meta2, [{var, _, context} = left, right] }, meta, [] } = ast, vars) do
    if { var, context } in vars do
      left_escaped = { :{}, [], tuple_to_list(left) }
      dot_escaped = { :{}, [], [:., meta2, [left_escaped, right]] }
      { :{}, meta, [dot_escaped, meta, []] }
    else
      ast
    end
  end

  # unary op
  def escape({ op, meta, [arg] }, vars) when op in @unary_ops do
    args = [escape(arg, vars)]
    { :{}, [], [op, meta, args] }
  end

  # binary op
  def escape({ op, meta, [left, right] }, vars) when op in @binary_ops do
    args = [escape(left, vars), escape(right, vars)]
    { :{}, [], [op, meta, args] }
  end

  # everything else is foreign or literals
  def escape(other, vars) do
    case find_vars(other, vars) do
      { var, _context } ->
        # TODO: Improve error message
        message = "bound vars are only allowed in dotted expression `#{var}.field` " <>
                  "or as argument to a query expression"
        raise ArgumentError, message: message
      nil -> other
    end
  end

  defp find_vars({ var, _, context }, vars) when is_atom(var) and is_atom(context) do
    if { var, context } in vars, do: { var, context }
  end

  defp find_vars({ left, _, right }, vars) do
    find_vars(left, vars) || find_vars(right, vars)
  end

  defp find_vars({ left, right }, vars) do
    find_vars(left, vars) || find_vars(right, vars)
  end

  defp find_vars(list, vars) when is_list(list) do
    Enum.find_value(list, find_vars(&1, vars))
  end

  defp find_vars(_, _vars) do
    nil
  end
end
