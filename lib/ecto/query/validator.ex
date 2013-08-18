defmodule Ecto.Query.Validator do
  @moduledoc false

  # This module does validation on the query checking that it's in a correct
  # format, raising if it's not.

  alias Ecto.Query.Util
  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr

  defrecord State, entities: [], vars: [], grouped: [], grouped?: false,
    in_agg?: false, apis: nil, from: nil

  # Adds type, file and line metadata to the exception
  defmacrop rescue_metadata(type, file, line, block) do
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

  def validate(Query[] = query, apis, opts) do
    if query.from == nil do
      raise Ecto.InvalidQuery, reason: "a query must have a from expression"
    end

    grouped = group_by_entities(query.group_bys, query.entities)
    is_grouped = query.group_bys != [] or query.havings != []
    state = State[entities: query.entities, grouped: grouped,
                  grouped?: is_grouped, apis: apis, from: query.from]

    validate_joins(query.joins, state)
    validate_wheres(query.wheres, state)
    validate_order_bys(query.order_bys, state)
    validate_group_bys(query.group_bys, state)
    validate_havings(query.havings, state)
    validate_preloads(query.preloads, state)

    unless opts[:skip_select] do
      validate_select(query.select, state)
      preload_selected(query)
    end
  end

  def validate_update(Query[] = query, apis, values) do
    validate_only_where(query)

    module = query.from

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
      state = State[entities: query.entities, apis: apis]
      type = type_check(expr, state)

      format_expected_type = Util.type_to_ast(expected_type) |> Macro.to_string
      format_type = Util.type_to_ast(type) |> Macro.to_string
      unless expected_type == type do
        raise Ecto.InvalidQuery, reason: "expected_type `#{format_expected_type}` " <>
        " on `#{module}.#{field}` doesn't match type `#{format_type}`"
      end
    end)

    validate(query, apis, skip_select: true)
  end

  def validate_delete(query, apis) do
    validate_only_where(query)
    validate(query, apis, skip_select: true)
  end

  def validate_get(query, apis) do
    validate_only_where(query)
    validate(query, apis, skip_select: true)
  end

  defp validate_only_where(query) do
    # Update validation check if assertion fails
    unquote(unless size(Query[]) == 12, do: raise "Ecto.Query.Query out of date")

    # TODO: File and line metadata
    unless match?(Query[joins: [], select: nil, order_bys: [], limit: nil,
        offset: nil, group_bys: [], havings: [], preloads: []], query) do
      raise Ecto.InvalidQuery, reason: "update query can only have a single `where` expression"
    end
  end

  defp validate_joins(joins, state) do
    state = state.grouped?(false)
    # Strip entity from query expr so we can reuse validate_booleans
    joins = Enum.map(joins, fn (expr) -> expr.update_expr(&elem(&1, 1)) end)
    validate_booleans(:join, joins, state)
  end

  defp validate_wheres(wheres, state) do
    state = state.grouped?(false)
    validate_booleans(:where, wheres, state)
  end

  defp validate_havings(havings, state) do
    validate_booleans(:having, havings, state)
  end

  defp validate_booleans(type, query_exprs, state) do
    Enum.each(query_exprs, fn(QueryExpr[] = expr) ->
      rescue_metadata(type, expr.file, expr.line) do
        expr_type = type_check(expr.expr, state)

        unless expr_type == :boolean do
          format_expr_type = Util.type_to_ast(expr_type) |> Macro.to_string
          raise Ecto.InvalidQuery, reason: "#{type} expression `#{Macro.to_string(expr.expr)}` " <>
            "is of type `#{format_expr_type}`, has to be of boolean type"
        end
      end
    end)
  end

  defp validate_order_bys(order_bys, state) do
    validate_field_list(:order_by, order_bys, state)
  end

  defp validate_group_bys(group_bys, state) do
    validate_field_list(:group_by, group_bys, state)
  end

  defp validate_field_list(type, query_exprs, state) do
    Enum.each(query_exprs, fn(QueryExpr[] = expr) ->
      rescue_metadata(type, expr.file, expr.line) do
        Enum.map(expr.expr, fn expr ->
          validate_field(expr, state)
        end)
      end
    end)
  end

  # order_by field
  defp validate_field({ _, var, field }, state) do
    validate_field({ var, field }, state)
  end

  # group_by field
  defp validate_field({ var, field }, State[] = state) do
    entity = Util.find_entity(state.entities, var)
    do_validate_field(entity, field)
  end

  defp do_validate_field(entity, field) do
    type = entity.__ecto__(:field_type, field)
    unless type do
      raise Ecto.InvalidQuery, reason: "unknown field `#{field}` on `#{inspect entity}`"
    end
  end

  defp validate_preloads(preloads, State[] = state) do
    Enum.each(preloads, fn(QueryExpr[] = expr) ->
      rescue_metadata(:preload, expr.file, expr.line) do
        Enum.map(expr.expr, fn field ->
          entity = state.from
          type = entity.__ecto__(:association, field)
          unless type do
            raise Ecto.InvalidQuery, reason: "`#{field}` is not an assocation field on `#{inspect entity}`"
          end
        end)
      end
    end)
  end

  defp validate_select(QueryExpr[] = expr, State[] = state) do
    rescue_metadata(:select, expr.file, expr.line) do
      select_clause(expr.expr, state)
    end
  end

  defp preload_selected(Query[select: select, preloads: preloads, from: from] = query) do
    unless preloads == [] do
      rescue_metadata(:select, select.file, select.line) do
        var = Util.from_entity_var(query)
        pos = Util.locate_var(select.expr, var)
        if nil?(pos) do
          raise Ecto.InvalidQuery, reason: "entity in from expression `#{from}` " <>
            "needs to be selected with preload query"
        end
      end
    end
  end

  # var.x
  defp type_check({ { :., _, [{ :&, _, [_] } = var, field] }, _, [] }, State[] = state) do
    entity = Util.find_entity(state.entities, var)
    check_grouped({ entity, field }, state)

    type = entity.__ecto__(:field_type, field)
    unless type do
      raise Ecto.InvalidQuery, reason: "unknown field `#{field}` on `#{inspect entity}`"
    end
    type
  end

  # var
  defp type_check({ :&, _, [_] } = var, State[] = state) do
    entity = Util.find_entity(state.entities, var)
    fields = entity.__ecto__(:field_names)
    Enum.each(fields, &check_grouped({ entity, &1 }, state))

    entity
  end

  # ops & functions
  defp type_check({ name, _, args } = expr, state) when is_atom(name) and is_list(args) do
    length_args = length(args)

    type = Enum.find_value(state.apis, fn(api) ->
      if api.aggregate?(name, length_args) do
        if state.in_agg? do
          raise Ecto.InvalidQuery, reason: "aggregate function calls cannot be nested"
        end
        state = state.in_agg?(true)
      end

      arg_types = Enum.map(args, &type_check(&1, state))

      if function_exported?(api, name, length_args) do
        case apply(api, name, arg_types) do
          { :ok, type } -> type
          { :error, allowed } ->
            raise Ecto.TypeCheckError, expr: expr, types: arg_types, allowed: allowed
        end
      end
    end)

    unless type do
      raise Ecto.InvalidQuery, reason: "function `#{name}/#{length_args}` not defined in query API"
    end
    type
  end

  # list
  defp type_check(list, state) when is_list(list) do
    types = Enum.map(list, &type_check(&1, state))

    case types do
      [] ->
        { :list, :any }
      [type|rest] ->
        unless Enum.all?(rest, &Util.type_eq?(type, &1)) do
          raise Ecto.InvalidQuery, reason: "all elements in list has to be of same type"
        end
        { :list, type }
    end
  end

  # atom
  defp type_check(literal, _vars) when is_atom(literal) and not (literal in [true, false, nil]) do
    raise Ecto.InvalidQuery, reason: "atoms are not allowed in queries `#{literal}`"
  end

  # values
  defp type_check(value, _state), do: Util.value_to_type(value)

  # Handle top level select cases

  defp select_clause({ left, right }, state) do
    select_clause(left, state)
    select_clause(right, state)
  end

  defp select_clause({ :{}, _, list }, state) do
    Enum.each(list, &select_clause(&1, state))
  end

  defp select_clause(list, state) when is_list(list) do
    Enum.each(list, &select_clause(&1, state))
  end

  defp select_clause(other, state) do
    type_check(other, state)
  end

  defp group_by_entities(group_bys, entities) do
    Enum.map(group_bys, fn(expr) ->
      Enum.map(expr.expr, fn({ var, field }) ->
        { Util.find_entity(entities, var), field }
      end)
    end) |> List.concat |> Enum.uniq
  end

  defp check_grouped(entity_field, state) do
    if state.grouped? and not state.in_agg? and not (entity_field in state.grouped) do
      { entity, field } = entity_field
      raise Ecto.InvalidQuery, reason: "`#{inspect entity}.#{field}` must appear in `group_by` " <>
        "or be used in an aggregate function"
    end
  end
end
