defmodule Ecto.Query.WhereBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  @unary_ops [ :not, :+, :- ]
  @binary_ops [ :==, :!=, :<=, :>=, :and, :or, :<, :>, :+, :-, :*, :/ ]

  # var.x - where var is bound
  def escape({ { :., meta2, [{var, _, context} = left, right] }, meta, [] } = ast, vars)
      when is_atom(var) and is_atom(context) do
    if var in vars do
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
    case BuilderUtil.find_vars(other, vars) do
      nil -> other
      var ->
        # TODO: Improve error message
        reason = "bound vars are only allowed in dotted expression `#{var}.field` " <>
                  "or as argument to a query expression"
        raise Ecto.InvalidQuery, reason: reason
    end
  end
end
