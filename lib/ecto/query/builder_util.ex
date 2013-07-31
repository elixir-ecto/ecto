defmodule Ecto.Query.BuilderUtil do
  @moduledoc false

  # Common functions for the query builder modules.

  @unary_ops [ :not, :+, :- ]
  @binary_ops [ :==, :!=, :<=, :>=, :and, :or, :<, :>, :+, :-, :*, :/, :in ]

  # Smart escapes a query expression. Everything that is a query expression will
  # be escaped, foreign (elixir) expressions will not be escaped so that they
  # will be evaluated in their place. This means that everything foreign will be
  # inserted as-is into the query.

  def escape(ast, vars), do: do_escape(ast, vars) |> elem(0)

  # var.x - where var is bound
  defp do_escape({ { :., meta2, [{var, _, context} = left, right] }, meta, [] } = ast, vars)
      when is_atom(var) and is_atom(context) do
    if var != :_ and var in vars do
      left_escaped = { :{}, [], tuple_to_list(left) }
      dot_escaped = { :{}, [], [:., meta2, [left_escaped, right]] }
      { { :{}, meta, [dot_escaped, meta, []] }, true }
    else
      { ast, false }
    end
  end

  # unary op
  defp do_escape({ op, meta, [arg] }, vars) when op in @unary_ops do
    { arg, is_escaped } = do_escape(arg, vars)
    if is_escaped do
      { { :{}, [], [op, meta, [arg]] }, true }
    else
      { { op, meta, [arg] }, false }
    end
  end

  # binary op
  defp do_escape({ op, meta, [left, right] }, vars) when op in @binary_ops do
    { left, is_escaped_left } = do_escape(left, vars)
    { right, is_escaped_right } = do_escape(right, vars)

    if is_escaped_left or is_escaped_right do
      { { :{}, [], [op, meta, [left, right]] }, true }
    else
      { { op, meta, [left, right] }, false }
    end
  end

  # range
  defp do_escape({ :.., meta, [left, right] }, vars) do
    { left, is_escaped_left } = do_escape(left, vars)
    { right, is_escaped_right } = do_escape(right, vars)

    if is_escaped_left or is_escaped_right do
      { { :.., meta, [left, right] }, true }
    else
      { { :.., meta, [left, right] }, false }
    end
  end

  # list
  defp do_escape(list, vars) when is_list(list) do
    Enum.map_reduce(list, false, fn(elem, acc) ->
      { arg, is_escaped } = do_escape(elem, vars)
      { arg, acc or is_escaped }
    end)
  end

  # everything else is foreign or literals
  defp do_escape(other, vars) do
    case find_vars(other, vars) do
      nil -> { other, false }
      var ->
        reason = "bound vars are only allowed in dotted expression `#{var}.field` " <>
          "or as argument to a query expression"
        raise Ecto.InvalidQuery, reason: reason
    end
  end

  # Return a variable in vars if found in AST, nil otherwise
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
    Enum.find_value(list, &find_vars(&1, vars))
  end

  def find_vars(_, _vars) do
    nil
  end
end
