defmodule Ecto.Query.Validator do
  @moduledoc false

  # This module does validation on the query checking that it's in a correct
  # format, raising if it's not.

  alias Ecto.Query.QueryUtil
  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr

  # Adds type, file and line metadata to the exception
  defmacrop rescue_metadata(type, query, file, line, block) do
    quote location: :keep do
      try do
        unquote(block)
      rescue e in [Ecto.InvalidQuery] ->
        stacktrace = System.stacktrace
        raise Ecto.InvalidQuery, [reason: e.reason, type: unquote(type),
          file: unquote(file), line: unquote(line)], stacktrace
      end
    end
  end

  def validate(Query[] = query) do
    if query.select == nil and length(query.froms) != 1 do
      reason = "a query must have a select expression if querying from more than one entity"
      raise Ecto.InvalidQuery, reason: reason
    end
    if query.froms == [] do
      raise Ecto.InvalidQuery, reason: "a query must have a from expression"
    end

    validate_wheres(query.wheres, query.froms)
    validate_select(query.select, query.froms)
  end

  defp validate_wheres(wheres, entities) do
    Enum.each(wheres, fn(QueryExpr[] = expr) ->
      rescue_metadata(:where, expr.expr, expr.file, expr.line) do
        vars = QueryUtil.merge_binding_vars(expr.binding, entities)
        unless type_expr(expr.expr, vars) == :boolean do
          raise Ecto.InvalidQuery, reason: "where expression has to be of boolean type"
        end
      end
    end)
  end

  defp validate_select(QueryExpr[] = expr, entities) do
    { _, select_expr } = expr.expr
    rescue_metadata(:select, select_expr, expr.file, expr.line) do
      vars = QueryUtil.merge_binding_vars(expr.binding, entities)
      type_expr(select_expr, vars)
    end
  end


  # var.x
  defp type_expr({ { :., _, [{ var, _, context }, field] }, _, [] }, vars)
      when is_atom(var) and is_atom(context) do
    entity = Keyword.fetch!(vars, var)
    type = entity.__ecto__(:field_type, field)

    unless type do
      raise Ecto.InvalidQuery, reason: "unknown field `#{var}.#{field}`"
    end

    if type == :integer or type == :float, do: :number, else: type
  end

  # var
  defp type_expr({ var, _, context}, vars) when is_atom(var) and is_atom(context) do
    Keyword.fetch!(vars, var) # ?
  end

  # unary op
  defp type_expr({ :not, _, [arg] }, vars) do
    type_arg = type_expr(arg, vars)
    unless type_arg == :boolean do
      raise Ecto.InvalidQuery, reason: "argument of `not` must be of type boolean"
    end
    :boolean
  end

  defp type_expr({ op, _, [arg] }, vars) when op in [:+, :-] do
    type_arg = type_expr(arg, vars)
    unless type_arg == :number do
      raise Ecto.InvalidQuery, reason: "argument of `#{op}` must be of a number type"
    end
    :number
  end

  # binary op
  defp type_expr({ op, _, [left, right] }, vars) when op in [:==, :!=] do
    type_left = type_expr(left, vars)
    type_right = type_expr(right, vars)
    unless type_left == type_right or type_left == :nil or type_right == :nil do
      raise Ecto.InvalidQuery, reason: "both arguments of `#{op}` types must match"
    end
    :boolean
  end

  defp type_expr({ op, _, [left, right] }, vars) when op in [:and, :or] do
    type_left = type_expr(left, vars)
    type_right = type_expr(right, vars)
    unless type_left == :boolean and type_right == :boolean do
      raise Ecto.InvalidQuery, reason: "both arguments of `#{op}` must be of type boolean"
    end
    :boolean
  end

  defp type_expr({ op, _, [left, right] }, vars) when op in [:<=, :>=, :<, :>] do
    type_left = type_expr(left, vars)
    type_right = type_expr(right, vars)
    unless type_left == :number and type_right == :number do
      raise Ecto.InvalidQuery, reason: "both arguments of `#{op}` must be of a number type"
    end
    :boolean
  end

  defp type_expr({ op, _, [left, right] }, vars) when op in [:+, :-, :*, :/] do
    type_left = type_expr(left, vars)
    type_right = type_expr(right, vars)
    unless type_left == :number and type_right == :number do
      raise Ecto.InvalidQuery, reason: "both arguments of `#{op}` must be of a number type"
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
  defp type_expr(literal, _vars) when is_binary(literal), do: :string

  defp type_expr(literal, _vars) when is_atom(literal) do
    raise Ecto.InvalidQuery, reason: "atoms are not allowed"
  end

  # unknown
  defp type_expr(expr, _vars) do
    raise Ecto.InvalidQuery, reason: "internal error on `#{inspect expr}"
  end
end
