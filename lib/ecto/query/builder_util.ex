defmodule Ecto.Query.BuilderUtil do
  @moduledoc false

  # Common functions for the query builder modules.

  @unary_ops [ :not, :+, :- ]
  @binary_ops [ :==, :!=, :<=, :>=, :and, :or, :<, :>, :+, :-, :*, :/, :in, :.. ]

  # Smart escapes a query expression. Everything that is a query expression will
  # be escaped, foreign (elixir) expressions will not be escaped so that they
  # will be evaluated in their place. This means that everything will foreign
  # will be inserted as-is into the query.

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
    case find_vars(other, vars) do
      nil -> other
      var ->
        # TODO: Improve error message
        reason = "bound vars are only allowed in dotted expression `#{var}.field` " <>
                  "or as argument to a query expression"
        raise Ecto.InvalidQuery, reason: reason
    end
  end

  # Returns all variables in the AST
  def find_vars({ var, _, context }, vars) when is_atom(var) and is_atom(context) do
    if var in vars, do: var
  end

  def find_vars({ left, _, right }, vars) do
    find_vars(left, vars) || find_vars(right, vars)
  end

  def find_vars({ left, right }, vars) do
    find_vars(left, vars) || find_vars(right, vars)
  end

  def find_vars(list, vars) when is_list(list) do
    Enum.find_value(list, find_vars(&1, vars))
  end

  def find_vars(_, _vars) do
    nil
  end
end
