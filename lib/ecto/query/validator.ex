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
      type = type_check(expr, state)

      format_expected_type = QueryUtil.type_to_ast(expected_type) |> Macro.to_string
      format_type = QueryUtil.type_to_ast(type) |> Macro.to_string
      unless expected_type == type do
        raise Ecto.InvalidQuery, reason: "expected_type `#{format_expected_type}` " <>
        " on `#{module}.#{field}` doesn't match type `#{format_type}`"
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
        expr_type = type_check(expr.expr, state)

        unless expr_type == :boolean do
          format_expr_type = QueryUtil.type_to_ast(expr_type) |> Macro.to_string
          raise Ecto.InvalidQuery, reason: "#{type} expression `#{Macro.to_string(expr.expr)}` " <>
            "is of type `#{format_expr_type}`, has to be of boolean type"
        end
      end
    end)
  end

  defp validate_select(QueryExpr[] = expr, State[froms: froms] = state) do
    { _, select_expr } = expr.expr
    rescue_metadata(:select, select_expr, expr.file, expr.line) do
      vars = QueryUtil.merge_binding_vars(expr.binding, froms)
      state = state.vars(vars)
      type_check(select_expr, state)
    end
  end

  # var.x
  defp type_check({ { :., _, [{ var, _, context }, field] }, _, [] }, State[] = state)
      when is_atom(var) and is_atom(context) do
    entity = Keyword.fetch!(state.vars, var)
    check_grouped(var, { entity, field }, state)

    type = entity.__ecto__(:field_type, field)
    unless type do
      raise Ecto.InvalidQuery, reason: "unknown field `#{var}.#{field}`"
    end
    type
  end

  # var
  defp type_check({ var, _, context}, State[] = state)
      when is_atom(var) and is_atom(context) do
    Keyword.fetch!(state.vars, var) # ?
  end

  # tuple
  defp type_check({ left, right }, state) do
    type_check({ :{}, [], [left, right] }, state)
  end

  # tuple
  defp type_check({ :{}, _, list }, _state) when is_list(list) do
    raise Ecto.InvalidQuery, reason: "tuples are not allowed in queries"
  end

  # ops & functions
  defp type_check({ name, _, args } = expr, state) when is_atom(name) and is_list(args) do
    arg_types = Enum.map(args, &type_check(&1, state))
    case apply(Ecto.Query.API, name, arg_types) do
      { :ok, type } -> type
      { :error, allowed } ->
        raise Ecto.TypeCheckError, expr: expr, types: arg_types, allowed: allowed
    end
  end

  # list
  defp type_check(list, state) when is_list(list) do
    types = Enum.map(list, &type_check(&1, state))

    case types do
      [] ->
        { :list, :any }
      [type|rest] ->
        unless Enum.all?(rest, &QueryUtil.type_eq?(type, &1)) do
          raise Ecto.InvalidQuery, reason: "all elements in list has to be of same type"
        end
        { :list, type }
    end
  end

  # atom
  defp type_check(literal, _vars) when is_atom(literal) and not (literal in [true, false, nil]) do
    raise Ecto.InvalidQuery, reason: "atoms are not allowed in queries"
  end

  # values
  defp type_check(value, _state), do: QueryUtil.value_to_type(value)

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
      raise Ecto.InvalidQuery, reason: "expression `#{var}.#{field}` must appear in `group_by` " <>
        "or be used in an aggregate function"
    end
  end
end
