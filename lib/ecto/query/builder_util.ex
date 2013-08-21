defmodule Ecto.Query.BuilderUtil do
  @moduledoc false

  # Common functions for the query builder modules.

  # Smart escapes a query expression. Everything that is a query expression will
  # be escaped, foreign (elixir) expressions will not be escaped so that they
  # will be evaluated in their place. This means that everything foreign will be
  # inserted as-is into the query.

  # var.x - where var is bound
  def escape({ { :., _, [{ var, _, context}, right] }, _, [] }, vars)
      when is_atom(var) and is_atom(context) do
    left_escaped = escape_var(var, vars)
    dot_escaped = { :{}, [], [:., [], [left_escaped, right]] }
    { :{}, [], [dot_escaped, [], []] }
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

  def escape_var(var, vars) do
    ix = Enum.find_index(vars, &(&1 == var))
    if var != :_ and ix do
      { :{}, [], [:&, [], [ix]] }
    else
      raise Ecto.InvalidQuery, reason: "variable `#{var}` needs to be bound"
    end
  end
end
