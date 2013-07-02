defmodule Ecto.Query.Validator do
  @moduledoc false

  def validate(query) do
    if query.select == nil do
      raise Ecto.InvalidQuery, message: "a query must have a select expression"
    end
    if query.froms == [] do
      raise Ecto.InvalidQuery, message: "a query must have a from expression"
    end

    validate_wheres(query.wheres, query.froms)
    validate_select(query.select, query.froms)
  end

  defp validate_wheres(wheres, vars) do
    Enum.each(wheres, fn(expr) ->
      unless type_expr(expr, vars) == :boolean do
        raise Ecto.InvalidQuery, message: "where expression has to be of boolean type"
      end
    end)
  end

  defp validate_select({ _, expr }, vars) do
    type_expr(expr, vars)
  end


  # var.x - where var is bound
  defp type_expr({ { :., _, [{ var, _, context }, field] }, _, [] }, vars)
      when is_atom(var) and is_atom(context) do
    entity = vars[var]

    unless entity do
      raise Ecto.InvalidQuery, message: "`#{var}` not bound in a from expression"
    end

    field_opts = entity.__ecto__(:fields, field)

    unless field_opts do
      raise Ecto.InvalidQuery, message: "unknown field `#{var}.#{field}`"
    end

    type = field_opts[:type]
    if type == :integer or type == :float, do: :number, else: type
  end

  # var - where var is bound
  defp type_expr({ var, _, context}, vars) when is_atom(var) and is_atom(context) do
    Keyword.fetch!(vars, var) # ?
  end

  # unary op
  defp type_expr({ :not, _, [arg] }, vars) do
    type_arg = type_expr(arg, vars)
    unless type_arg == :boolean do
      raise Ecto.InvalidQuery, message: "argument of `not` must be of type boolean"
    end
    :boolean
  end

  defp type_expr({ op, _, [arg] }, vars) when op in [:+, :-] do
    type_arg = type_expr(arg, vars)
    unless type_arg == :number do
      raise Ecto.InvalidQuery, message: "argument of `#{op}` must be of a number type"
    end
    :number
  end

  # binary op
  defp type_expr({ op, _, [left, right] }, vars) when op in [:==, :!=] do
    type_left = type_expr(left, vars)
    type_right = type_expr(right, vars)
    unless type_left == type_right or type_left == :nil or type_right == :nil do
      raise Ecto.InvalidQuery, message: "both arguments of `#{op}` types must match"
    end
    :boolean
  end

  defp type_expr({ op, _, [left, right] }, vars) when op in [:and, :or] do
    type_left = type_expr(left, vars)
    type_right = type_expr(right, vars)
    unless type_left == :boolean and type_right == :boolean do
      raise Ecto.InvalidQuery, message: "both arguments of `#{op}` must be of type boolean"
    end
    :boolean
  end

  defp type_expr({ op, _, [left, right] }, vars) when op in [:<=, :>=, :<, :>] do
    type_left = type_expr(left, vars)
    type_right = type_expr(right, vars)
    unless type_left == :number and type_right == :number do
      raise Ecto.InvalidQuery, message: "both arguments of `#{op}` must be of a number type"
    end
    :boolean
  end

  defp type_expr({ op, _, [left, right] }, vars) when op in [:+, :-, :*, :/] do
    type_left = type_expr(left, vars)
    type_right = type_expr(right, vars)
    unless type_left == :number and type_right == :number do
      raise Ecto.InvalidQuery, message: "both arguments of `#{op}` must be of a number type"
    end
    :number
  end

  defp type_expr(list, vars) when is_list(list) do
    Enum.each(list, type_expr(&1, vars))
    :list
  end

  defp type_expr({ left, right }, vars) do
    type_expr({ :{}, [], [left, right] }, vars)
  end

  defp type_expr({ :{}, _, list }, vars) do
    Enum.each(list, type_expr(&1, vars))
    :tuple
  end

  # literals
  defp type_expr(nil, _vars), do: :nil
  defp type_expr(false, _vars), do: :boolean
  defp type_expr(true, _vars), do: :boolean
  defp type_expr(literal, _vars) when is_number(literal), do: :number
  defp type_expr(literal, _vars) when is_atom(literal),   do: :string
  defp type_expr(literal, _vars) when is_binary(literal), do: :string

  # unknown
  defp type_expr(expr, _vars) do
    raise Ecto.InvalidQuery, message: "internal error on `#{inspect expr}"
  end
end
