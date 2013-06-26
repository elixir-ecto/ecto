defmodule Ecto.Query.SelectBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  @unary_ops [ :+, :- ]
  @binary_ops [ :==, :!=, :<=, :>=, :<, :>, :+, :-, :*, :/ ]

  def escape({ left, right }, vars) do
    { :tuple, [sub_escape(left, vars), sub_escape(right, vars)] }
  end

  def escape({ :{}, _, list }, vars) do
    { :tuple, Enum.map(list, sub_escape(&1, vars)) }
  end

  def escape({ :__block__, _, [ast] }, vars) do
    escape(ast, vars)
  end

  def escape(list, vars) when is_list(list) do
    { :list, Enum.map(list, sub_escape(&1, vars)) }
  end

  def escape(other, vars) do
    { :single, sub_escape(other, vars) }
  end

   # var.x - where var is bound
  defp sub_escape({ { :., meta2, [{var, _, context} = left, right] }, meta, []} = ast, vars)
      when is_atom(var) and is_atom(context) do
    if var in vars do
      left_escaped = { :{}, [], tuple_to_list(left) }
      dot_escaped = { :{}, [], [:., meta2, [left_escaped, right]] }
      { :{}, [], [dot_escaped, meta, []] }
    else
      ast
    end
  end

  # var - where var is bound
  defp sub_escape({ var, _, context} = ast, vars) when is_atom(var) and is_atom(context) do
    if var in vars do
      { :{}, [], tuple_to_list(ast) }
    else
      ast
    end
  end

  # unary op
  defp sub_escape({ op, meta, [arg] }, vars) when op in @unary_ops do
    args = [sub_escape(arg, vars)]
    { :{}, [], [op, meta, args] }
  end

  # binary op
  defp sub_escape({ op, meta, [left, right] }, vars) when op in @binary_ops do
    args = [sub_escape(left, vars), sub_escape(right, vars)]
    { :{}, [], [op, meta, args] }
  end

  # everything else is foreign or literals
  defp sub_escape(other, vars) do
    case BuilderUtil.find_vars(other, vars) do
      nil -> other
      var ->
        # TODO: Improve error message
        message = "bound vars are only allowed in dotted expression `#{var}.field` " <>
                  "or as argument to a query expression"
        raise ArgumentError, message: message
    end
  end
end
