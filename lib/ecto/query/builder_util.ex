defmodule Ecto.Query.BuilderUtil do
  @moduledoc false

  # Common functions for the query builder modules.

  # Smart escapes a query expression. Everything that is a query expression will
  # be escaped, foreign (elixir) expressions will not be escaped so that they
  # will be evaluated in their place. This means that everything foreign will be
  # inserted as-is into the query.

  # var.x - where var is bound
  def escape({ { :., meta2, [{var, _, context} = left, right] }, meta, [] }, vars)
      when is_atom(var) and is_atom(context) do
    if var != :_ and var in vars do
      left_escaped = { :{}, [], tuple_to_list(left) }
      dot_escaped = { :{}, [], [:., meta2, [left_escaped, right]] }
      { :{}, meta, [dot_escaped, meta, []] }
    else
      raise Ecto.InvalidQuery, reason: "variable `#{var}` needs to be bound in a from expression"
    end
  end

  # interpolation
  def escape({ :^, _, [arg] }, _vars) do
    arg
  end

  # ops & functions
  def escape({ name, meta, args }, vars) when is_atom(name) and is_list(args) do
    args = Enum.map(args, &escape(&1, vars))
    { :{}, [], [name, meta, args] }
  end

  # list
  def escape(list, vars) when is_list(list) do
    Enum.map(list, &escape(&1, vars))
  end

  # literals
  def escape(literal, _vars) when is_binary(literal), do: literal
  def escape(literal, _vars) when is_boolean(literal), do: literal
  def escape(literal, _vars) when is_number(literal), do: literal
  def escape(nil, _vars), do: nil

  # everything else is not allowed
  def escape(other, _vars) do
    raise Ecto.InvalidQuery, reason: "`#{Macro.to_string(other)}` is not a valid query expression"
  end
end
