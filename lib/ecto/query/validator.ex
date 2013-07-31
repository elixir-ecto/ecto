defmodule Ecto.Query.Validator do
  @moduledoc false

  # This module does validation on the query checking that it's in a correct
  # format, raising if it's not.

  alias Ecto.Query.QueryUtil
  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr

  defrecord State, froms: [], vars: [], grouped: [], is_grouped: false

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

  def validate(Query[] = query, opts) do
    if !opts[:skip_select] and (query.select == nil and length(query.froms) != 1) do
      reason = "a query must have a select expression if querying from more than one entity"
      raise Ecto.InvalidQuery, reason: reason
    end
    if query.froms == [] do
      raise Ecto.InvalidQuery, reason: "a query must have a from expression"
    end

    grouped = group_by_entities(query.group_bys, query.froms)
    is_grouped = query.group_bys != [] or query.havings != []
    state = State[froms: query.froms, grouped: grouped, is_grouped: is_grouped]

    validate_havings(query.havings, state)
    validate_wheres(query.wheres, state)
    unless opts[:skip_select], do: validate_select(query.select, state)
  end

  def validate_update(Query[] = query, binds, values) do
    validate_only_from_where(query)

    module = Enum.first(query.froms)

    if values == [] do
      raise Ecto.InvalidQuery, reason: "no values to update given"
    end

    Enum.each(values, fn({ field, expr }) ->
      expected_type = module.__ecto__(:field_type, field)

      unless expected_type do
        raise Ecto.InvalidQuery, reason: "field `#{field}` is not on the " <>
          "entity `#{module}`"
      end

      # TODO: Check if entity field allows nil
      vars = QueryUtil.merge_binding_vars(binds, [module])
      state = State[froms: query.froms, vars: vars]
      type = type_expr(expr, state)

      if expected_type in [:integer, :float], do: expected_type = :number
      unless expected_type == type do
        raise Ecto.InvalidQuery, reason: "expected_type `#{expected_type}` " <>
        " on `#{module}.#{field}` doesn't match type `#{type}`"
      end
    end)

    validate(query, skip_select: true)
  end

  def validate_delete(query) do
    validate_only_from_where(query)
    validate(query, skip_select: true)
  end

  def validate_get(query) do
    validate_only_from_where(query)
    validate(query, skip_select: true)
  end

  defp validate_only_from_where(query) do
    # Update validation check if assertion fails
    unquote(unless size(Query[]) == 9, do: raise "Ecto.Query.Query out of date")

    # TODO: File and line metadata
    unless match?(Query[froms: [_], select: nil, order_bys: [], limit: nil,
        offset: nil, group_bys: [], havings: []], query) do
      raise Ecto.InvalidQuery, reason: "update query can only have a single `from` " <>
        " and `where` expressions"
    end
  end

  defp validate_wheres(wheres, state) do
    state = state.is_grouped(false)
    validate_booleans(:where, wheres, state)
  end

  defp validate_havings(havings, state) do
    validate_booleans(:having, havings, state)
  end

  defp validate_booleans(type, query_exprs, State[froms: froms] = state) do
    Enum.each(query_exprs, fn(QueryExpr[] = expr) ->
      rescue_metadata(type, expr.expr, expr.file, expr.line) do
        vars = QueryUtil.merge_binding_vars(expr.binding, froms)
        state = state.vars(vars)
        unless type_expr(expr.expr, state) == :boolean do
          raise Ecto.InvalidQuery, reason: "#{type} expression has to be of boolean type"
        end
      end
    end)
  end

  defp validate_select(QueryExpr[] = expr, State[froms: froms] = state) do
    { _, select_expr } = expr.expr
    rescue_metadata(:select, select_expr, expr.file, expr.line) do
      vars = QueryUtil.merge_binding_vars(expr.binding, froms)
      state = state.vars(vars)
      type_expr(select_expr, state)
    end
  end

  # var.x
  defp type_expr({ { :., _, [{ var, _, context }, field] }, _, [] }, State[] = state)
      when is_atom(var) and is_atom(context) do
    entity = Keyword.fetch!(state.vars, var)
    check_grouped(var, { entity, field }, state)

    type = entity.__ecto__(:field_type, field)

    unless type do
      raise Ecto.InvalidQuery, reason: "unknown field `#{var}.#{field}`"
    end

    if type in [:integer, :float], do: :number, else: type
  end

  # var
  defp type_expr({ var, _, context}, State[] = state)
      when is_atom(var) and is_atom(context) do
    Keyword.fetch!(state.vars, var) # ?
  end

  # unary op
  defp type_expr({ :not, _, [arg] }, state) do
    type_arg = type_expr(arg, state)
    unless type_arg == :boolean do
      raise Ecto.InvalidQuery, reason: "argument of `not` must be of type boolean"
    end
    :boolean
  end

  defp type_expr({ op, _, [arg] }, state) when op in [:+, :-] do
    type_arg = type_expr(arg, state)
    unless type_arg == :number do
      raise Ecto.InvalidQuery, reason: "argument of `#{op}` must be of a number type"
    end
    :number
  end

  # binary op
  defp type_expr({ op, _, [left, right] }, state) when op in [:==, :!=] do
    type_left = type_expr(left, state)
    type_right = type_expr(right, state)
    unless type_left == type_right or type_left == :nil or type_right == :nil do
      raise Ecto.InvalidQuery, reason: "both arguments of `#{op}` types must match"
    end
    :boolean
  end

  defp type_expr({ op, _, [left, right] }, state) when op in [:and, :or] do
    type_left = type_expr(left, state)
    type_right = type_expr(right, state)
    unless type_left == :boolean and type_right == :boolean do
      raise Ecto.InvalidQuery, reason: "both arguments of `#{op}` must be of type boolean"
    end
    :boolean
  end

  defp type_expr({ op, _, [left, right] }, state) when op in [:<=, :>=, :<, :>] do
    type_left = type_expr(left, state)
    type_right = type_expr(right, state)
    unless type_left == :number and type_right == :number do
      raise Ecto.InvalidQuery, reason: "both arguments of `#{op}` must be of a number type"
    end
    :boolean
  end

  defp type_expr({ op, _, [left, right] }, state) when op in [:+, :-, :*, :/] do
    type_left = type_expr(left, state)
    type_right = type_expr(right, state)
    unless type_left == :number and type_right == :number do
      raise Ecto.InvalidQuery, reason: "both arguments of `#{op}` must be of a number type"
    end
    :number
  end

  defp type_expr({ :in, _, [_left, right] }, state) do
    type_right = type_expr(right, state)
    unless type_right == :list do
      raise Ecto.InvalidQuery, reason: "second argument of `in` must be of list type"
    end
    :boolean
  end

  defp type_expr(Range[first: left, last: right], state) do
    type_left = type_expr(left, state)
    type_right = type_expr(right, state)
    unless type_left == :number and type_right == :number do
      raise Ecto.InvalidQuery, reason: "both arguments of `..` must be of a number type"
    end
    :list
  end

  defp type_expr(list, state) when is_list(list) do
    Enum.each(list, type_expr(&1, state))
    :list
  end

  defp type_expr({ left, right }, state) do
    type_expr({ :{}, [], [left, right] }, state)
  end

  defp type_expr({ :{}, _, list }, state) do
    Enum.each(list, type_expr(&1, state))
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
    raise Ecto.InvalidQuery, reason: "internal error on `#{inspect expr}`"
  end

  defp group_by_entities(group_bys, froms) do
    Enum.map(group_bys, fn(QueryExpr[] = group_by) ->
      vars = QueryUtil.merge_binding_vars(group_by.binding, froms)
      Enum.map(group_by.expr, fn({ var, field }) ->
        { Keyword.fetch!(vars, var), field }
      end)
    end) |> List.concat |> Enum.uniq
  end

  defp check_grouped(var, entity_field, state) do
    if state.is_grouped and not (entity_field in state.grouped) do
      { _, field } = entity_field
      raise Ecto.InvalidQuery, reason: "`#{var}.#{field}` must appear in `group_by` " <>
        "or be used in an aggregate function"
    end
  end
end
