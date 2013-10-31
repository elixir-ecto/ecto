defmodule Ecto.Query.Validator do
  @moduledoc false

  # This module does validation on the query checking that it's in a correct
  # format, raising if it's not.

  alias Ecto.Query.Util
  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.JoinExpr
  alias Ecto.Query.AssocJoinExpr

  defrecord State, sources: [], vars: [], grouped: [], grouped?: false,
    in_agg?: false, apis: nil, from: nil, query: nil

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

    grouped = group_by_sources(query.group_bys, query.sources)
    is_grouped = query.group_bys != [] or query.havings != []
    state = State[sources: query.sources, grouped: grouped, grouped?: is_grouped,
                  apis: apis, from: query.from, query: query]

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

    if values == [] do
      raise Ecto.InvalidQuery, reason: "no values to update given"
    end

    if entity = Util.entity(query.from) do
      Enum.each(values, fn { field, expr } ->
        expected_type = entity.__entity__(:field_type, field)

        unless expected_type do
          raise Ecto.InvalidQuery, reason: "field `#{field}` is not on the " <>
            "entity `#{inspect entity}`"
        end

        # TODO: Check if entity field allows nil
        state = State[sources: query.sources, apis: apis]
        type = type_check(expr, state)

        format_expected_type = Util.type_to_ast(expected_type) |> Macro.to_string
        format_type = Util.type_to_ast(type) |> Macro.to_string
        unless expected_type == type do
          raise Ecto.InvalidQuery, reason: "expected_type `#{format_expected_type}` " <>
          " on `#{inspect entity}.#{field}` doesn't match type `#{format_type}`"
        end
      end)
    end

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

    { joins, assocs } = Enum.partition(joins, fn
      JoinExpr[on: nil] ->
        raise Ecto.InvalidQuery, reason: "an `on` query expression have to " <>
          "follow a `join` unless it's an association join"
      JoinExpr[] -> true
      AssocJoinExpr[] -> false
    end)

    ons = Enum.map(joins, &(&1.on))
    validate_booleans(:join_on, ons, state)
    validate_assoc_joins(assocs, state)
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

        unless expr_type in [:unknown, :boolean] do
          format_expr_type = Util.type_to_ast(expr_type) |> Macro.to_string
          raise Ecto.InvalidQuery, reason: "#{type} expression `#{Macro.to_string(expr.expr)}` " <>
            "is of type `#{format_expr_type}`, has to be of boolean type"
        end
      end
    end)
  end

  defp validate_assoc_joins(joins, State[] = state) do
    Enum.each(joins, fn AssocJoinExpr[] = expr ->
      rescue_metadata(:join, expr.file, expr.line) do
        { :., _, [left, right] } = expr.expr
        entity = Util.find_source(state.sources, left) |> Util.entity

        if nil?(entity) do
          raise Ecto.InvalidQuery, reason: "association join can only be performed " <>
            "on fields from an entity"
        end

        refl = entity.__entity__(:association, right)
        unless refl do
          raise Ecto.InvalidQuery, reason: "association join can only be performed " <>
            "on assocation fields"
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
    entity = Util.find_source(state.sources, var) |> Util.entity
    if entity, do: do_validate_field(entity, field)
  end

  defp do_validate_field(entity, field) do
    type = entity.__entity__(:field_type, field)
    unless type do
      raise Ecto.InvalidQuery, reason: "unknown field `#{field}` on `#{inspect entity}`"
    end
  end

  defp validate_preloads(preloads, State[] = state) do
    entity = Util.entity(state.from)

    if preloads != [] and nil?(entity) do
      raise Ecto.InvalidQuery, reason: "can only preload on fields from an entity"
    end

    Enum.each(preloads, fn(QueryExpr[] = expr) ->
      rescue_metadata(:preload, expr.file, expr.line) do
        Enum.map(expr.expr, fn field ->
          type = entity.__entity__(:association, field)
          unless type do
            raise Ecto.InvalidQuery, reason: "`#{inspect entity}.#{field}` is not an association field"
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

  defp preload_selected(Query[select: select, preloads: preloads]) do
    unless preloads == [] do
      rescue_metadata(:select, select.file, select.line) do
        pos = Util.locate_var(select.expr, { :&, [], [0] })
        if nil?(pos) do
          raise Ecto.InvalidQuery, reason: "source in from expression " <>
            "needs to be selected when using preload query"
        end
      end
    end
  end

  # var.x
  defp type_check({ { :., _, [{ :&, _, [_] } = var, field] }, _, [] }, State[] = state) do
    source = Util.find_source(state.sources, var)
    check_grouped({ source, field }, state)

    if entity = Util.entity(source) do
      type = entity.__entity__(:field_type, field)
      unless type do
        raise Ecto.InvalidQuery, reason: "unknown field `#{field}` on `#{inspect entity}`"
      end
      type
    else
      :unknown
    end
  end

  # var
  defp type_check({ :&, _, [_] } = var, State[] = state) do
    source = Util.find_source(state.sources, var)
    if entity = Util.entity(source) do
      fields = entity.__entity__(:field_names)
      Enum.each(fields, &check_grouped({ source, &1 }, state))
      entity
    else
      source = Util.source(source)
      raise Ecto.InvalidQuery, reason: "cannot select on source, `#{inspect source}`, with no entity"
    end
  end

  # ops & functions
  defp type_check({ name, _, args } = expr, state) when is_atom(name) and is_list(args) do
    length_args = length(args)

    api = Enum.find(state.apis, &function_exported?(&1, name, length_args))
    unless api do
      raise Ecto.InvalidQuery, reason: "function `#{name}/#{length_args}` not defined in query API"
    end

    is_agg = api.aggregate?(name, length_args)
    if is_agg and state.in_agg? do
      raise Ecto.InvalidQuery, reason: "aggregate function calls cannot be nested"
    end

    state = state.in_agg?(is_agg)
    arg_types = Enum.map(args, &type_check(&1, state))

    if Enum.any?(arg_types, &(&1 == :unknown)) do
      :unknown
    else
      case apply(api, name, arg_types) do
        { :ok, type } ->
          type
        { :error, allowed } ->
          raise Ecto.TypeCheckError, expr: expr, types: arg_types, allowed: allowed
      end
    end
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
  defp type_check(value, _state) do
    case Util.value_to_type(value) do
      { :ok, type } -> type
      { :error, reason } ->
        raise Ecto.InvalidQuery, reason: reason
    end
  end

  # Handle top level select cases

  defp select_clause({ :assoc, _, [parent, child] }, State[] = state) do
    entity = Util.find_source(state.sources, parent) |> Util.entity
    unless entity == Util.entity(state.from) do
      raise Ecto.InvalidQuery, reason: "can only associate on the from entity"
    end

    expr = Util.find_expr(state.query, child)
    unless match?(AssocJoinExpr[qual: qual] when qual in [:inner, :left], expr) do
      raise Ecto.InvalidQuery, reason: "can only associate on an inner or left association join"
    end
  end

  # Some two-tuples may be records (ex. Ecto.Binary[]), so check for records
  # explicitly. We can do this because we don't allow atoms in queries.
  defp select_clause({ atom, _ } = record, state) when is_atom(atom) do
    type_check(record, state)
  end

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

  defp group_by_sources(group_bys, sources) do
    Enum.map(group_bys, fn(expr) ->
      Enum.map(expr.expr, fn({ var, field }) ->
        source = Util.find_source(sources, var)
        { source, field }
      end)
    end) |> Enum.concat |> Enum.uniq
  end

  defp check_grouped({ source, field } = source_field, state) do
    if state.grouped? and not state.in_agg? and not (source_field in state.grouped) do
      entity = Util.entity(source) || Util.source(source)
      raise Ecto.InvalidQuery, reason: "`#{inspect entity}.#{field}` must appear in `group_by` " <>
        "or be used in an aggregate function"
    end
  end
end
