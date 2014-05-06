defmodule Ecto.Query.Validator do
  @moduledoc false

  # This module does validation on the query checking that it's in
  # a correct format, raising if it's not.

  # TODO: Check it raises on missing bindings

  alias Ecto.Query
  alias Ecto.Query.Util
  alias Ecto.Query.JoinExpr
  alias Ecto.Associations.Assoc

  # Adds type, file and line metadata to the exception
  defmacrop rescue_metadata(type, file, line, block) do
    quote location: :keep do
      try do
        unquote(block)
      rescue e in [Ecto.QueryError] ->
        stacktrace = System.stacktrace
        raise Ecto.QueryError, [reason: e.reason, type: unquote(type),
          file: unquote(file), line: unquote(line)], stacktrace
      end
    end
  end

  def validate(query, apis, opts \\ []) do
    if query.from == nil do
      raise Ecto.QueryError, reason: "a query must have a from expression"
    end

    grouped = exprs_sources(query.group_bys, query.sources)
    is_grouped = query.group_bys != [] or query.havings != []
    state = Map.merge(new_state,
                      %{sources: query.sources, grouped: grouped, grouped?: is_grouped,
                        apis: apis, from: query.from, query: query})

    validate_joins(query.joins, state)
    validate_wheres(query.wheres, state)
    validate_order_bys(query.order_bys, state)
    validate_group_bys(query.group_bys, state)
    validate_havings(query.havings, state)
    validate_preloads(query.preloads, state)

    unless opts[:skip_select] do
      validate_select(query.select, state)
      validate_distincts(query, state)
      preload_selected(query)
    end
  end

  def validate_update(query, apis, values) do
    validate_only_where(query)

    if values == [] do
      raise Ecto.QueryError, reason: "no values to update given"
    end

    if model = Util.model(query.from) do
      Enum.each(values, fn {field, expr} ->
        expected_type = model.__schema__(:field_type, field)

        unless expected_type do
          raise Ecto.QueryError, reason: "field `#{field}` is not on the " <>
            "model `#{inspect model}`"
        end

        # TODO: Check if model field allows nil
        state = Map.merge(new_state, %{sources: query.sources, apis: apis})
        type = type_check(expr, state)

        format_expected_type = Util.type_to_ast(expected_type) |> Macro.to_string
        format_type = Util.type_to_ast(type) |> Macro.to_string
        unless expected_type == type do
          raise Ecto.QueryError, reason: "expected_type `#{format_expected_type}` " <>
          " on `#{inspect model}.#{field}` doesn't match type `#{format_type}`"
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
    unquote(unless map_size(%Query{}) == 14, do: raise "Ecto.Query out of date")

    # TODO: File and line metadata
    unless match?(%Query{joins: [], select: nil, order_bys: [], limit: nil,
        offset: nil, group_bys: [], havings: [], preloads: [], distincts: [], lock: nil}, query) do
      raise Ecto.QueryError, reason: "query can only have `where` expressions"
    end
  end

  defp validate_joins(joins, state) do
    state = %{state | grouped?: false}
    ons = Enum.map(joins, &(&1.on))
    validate_booleans(:join_on, ons, state)
  end

  defp validate_wheres(wheres, state) do
    state = %{state | grouped?: false}
    validate_booleans(:where, wheres, state)
  end

  defp validate_havings(havings, state) do
    validate_booleans(:having, havings, state)
  end

  defp validate_booleans(type, query_exprs, state) do
    Enum.each(query_exprs, fn(expr) ->
      rescue_metadata(type, expr.file, expr.line) do
        expr_type = type_check(expr.expr, state)

        unless expr_type in [:unknown, :boolean] do
          format_expr_type = Util.type_to_ast(expr_type) |> Macro.to_string
          raise Ecto.QueryError, reason: "#{type} expression `#{Macro.to_string(expr.expr)}` " <>
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
    Enum.each(query_exprs, fn(expr) ->
      rescue_metadata(type, expr.file, expr.line) do
        Enum.map(expr.expr, fn expr ->
          validate_field(expr, state)
        end)
      end
    end)
  end

  # order_by field
  defp validate_field({_, var, field}, state) do
    validate_field({var, field}, state)
  end

  # group_by field
  defp validate_field({var, field}, %{sources: sources}) do
    model = Util.find_source(sources, var) |> Util.model
    if model, do: do_validate_field(model, field)
  end

  defp do_validate_field(model, field) do
    type = model.__schema__(:field_type, field)
    unless type do
      raise Ecto.QueryError, reason: "unknown field `#{field}` on `#{inspect model}`"
    end
  end

  defp validate_preloads(preloads, %{from: from}) do
    model = Util.model(from)

    if preloads != [] and nil?(model) do
      raise Ecto.QueryError, reason: "can only preload on fields from a model"
    end

    Enum.each(preloads, fn(expr) ->
      rescue_metadata(:preload, expr.file, expr.line) do
        check_preload_fields(expr.expr, model)
      end
    end)
  end

  defp check_preload_fields(fields, model) do
    Enum.map(fields, fn {field, sub_fields} ->
      refl = model.__schema__(:association, field)
      unless refl do
        raise Ecto.QueryError, reason: "`#{inspect model}.#{field}` is not an association field"
      end
      check_preload_fields(sub_fields, refl.associated)
    end)
  end

  defp validate_select(expr, state) do
    rescue_metadata(:select, expr.file, expr.line) do
      select_clause(expr.expr, state)
    end
  end

  defp validate_distincts(%Query{order_bys: order_bys, distincts: distincts, sources: sources}, state) do
    validate_field_list(:distinct, distincts, state)

    # ensure that the fields in `distinct` appears before other fields in the `order_by` expression

    # ex: distinct: id, title / order_by: title, id => no error
    #     distinct: title / order_by: id => raise (title not in order_by)
    #     distinct: title / order_by: id, title => raise (title in order_by but not leftmost part)

    distincts =
      Enum.map(distincts, fn expr ->
        Enum.map(expr.expr, fn {var, field} ->
          source = Util.find_source(sources, var) |> Util.source
          {source, field, {expr.file, expr.line}}
        end)
      end) |> Enum.concat

    order_bys =
      order_bys_sources(order_bys, sources)
      |> Enum.map(fn {{source, _}, field} -> {source, field} end)

    do_validate_distincts(distincts, order_bys)
  end

  defp do_validate_distincts([], _), do: :ok

  defp do_validate_distincts(_, []), do: :ok

  defp do_validate_distincts(distincts, [{source, field} | order_bys]) do
    filter = fn
      {s, f, _} when s == source and f == field -> true
      _ -> false
    end

    in_distinct? =  Enum.any?(distincts, filter)

    if in_distinct? do
      distincts = Enum.reject(distincts, filter)
      do_validate_distincts(distincts, order_bys)
    else
      {_, _, {file, line}} = Enum.at(distincts, 0)
      raise Ecto.QueryError, reason: "the `order_by` expression should first reference " <>
        "all the `distinct` fields before other fields", type: :distinct, file: file, line: line
    end
  end

  defp preload_selected(%Query{select: select, preloads: preloads}) do
    unless preloads == [] do
      rescue_metadata(:select, select.file, select.line) do
        pos = Util.locate_var(select.expr, {:&, [], [0]})
        if nil?(pos) do
          raise Ecto.QueryError, reason: "source in from expression " <>
            "needs to be selected when using preload query"
        end
      end
    end
  end

  # var.x
  defp type_check({{:., _, [{:&, _, [_]} = var, field]}, _, []}, %{sources: sources} = state) do
    source = Util.find_source(sources, var)
    check_grouped({source, field}, state)

    if model = Util.model(source) do
      type = model.__schema__(:field_type, field)
      unless type do
        raise Ecto.QueryError, reason: "unknown field `#{field}` on `#{inspect model}`"
      end
      type
    else
      :unknown
    end
  end

  # var
  defp type_check({:&, _, [_]} = var, %{sources: sources} = state) do
    source = Util.find_source(sources, var)
    if model = Util.model(source) do
      fields = model.__schema__(:field_names)
      Enum.each(fields, &check_grouped({source, &1}, state))
      model
    else
      source = Util.source(source)
      raise Ecto.QueryError, reason: "cannot select on source, `#{inspect source}`, with no model"
    end
  end

  # ops & functions
  defp type_check({name, _, args} = expr, %{apis: apis, in_agg?: in_agg?} = state)
      when is_atom(name) and is_list(args) do
    length_args = length(args)

    api = Enum.find(apis, &function_exported?(&1, name, length_args))
    unless api do
      raise Ecto.QueryError, reason: "function `#{name}/#{length_args}` not defined in query API"
    end

    is_agg = api.aggregate?(name, length_args)
    if is_agg and in_agg? do
      raise Ecto.QueryError, reason: "aggregate function calls cannot be nested"
    end

    state = %{state | in_agg?: is_agg}
    arg_types = Enum.map(args, &type_check(&1, state))

    if Enum.any?(arg_types, &(&1 == :unknown)) do
      :unknown
    else
      case apply(api, name, arg_types) do
        {:ok, type} ->
          type
        {:error, allowed} ->
          raise Ecto.Query.TypeCheckError, expr: expr, types: arg_types, allowed: allowed
      end
    end
  end

  # list
  defp type_check(list, _state) when is_list(list) do
    list = inspect(list, no_char_lists: true)
    raise Ecto.QueryError, reason: "lists `#{list}` are not allowed in queries, " <>
      "wrap in `array/2` instead"
  end

  # atom
  defp type_check(atom, _state) when is_atom(atom) and not (atom in [true, false, nil]) do
    raise Ecto.QueryError, reason: "atoms are not allowed in queries `#{inspect atom}`"
  end

  # values
  defp type_check(value, state) do
    if Util.literal?(value) do
      case Util.value_to_type(value, &{:ok, type_check(&1, state)}) do
        {:ok, type} ->
          type
        {:error, reason} ->
          raise Ecto.QueryError, reason: reason
      end
    else
      raise Ecto.QueryError, reason: "`unknown type of value `#{inspect value}`"
    end
  end

  # Handle top level select cases

  defp select_clause({:assoc, _, [var, fields]}, %{from: from, sources: sources} = state) do
    model = Util.find_source(sources, var) |> Util.model
    unless model == Util.model(from) do
      raise Ecto.QueryError, reason: "can only associate on the from model"
    end

    assoc_select(var, fields, state)
  end

  # Some two-tuples may be records (ex. Ecto.Binary[]), so check for records
  # explicitly. We can do this because we don't allow atoms in queries.
  defp select_clause({atom, _} = record, state) when is_atom(atom) do
    type_check(record, state)
  end

  defp select_clause({left, right}, state) do
    select_clause(left, state)
    select_clause(right, state)
  end

  defp select_clause({:{}, _, list}, state) do
    Enum.each(list, &select_clause(&1, state))
  end

  defp select_clause(list, state) when is_list(list) do
    Enum.each(list, &select_clause(&1, state))
  end

  defp select_clause(other, state) do
    type_check(other, state)
  end

  defp assoc_select(parent_var, fields, %{query: query, sources: sources} = state) do
    Enum.each(fields, fn {field, nested} ->
      {child_var, nested_fields} = Assoc.decompose_assoc(nested)
      parent_model = Util.find_source(sources, parent_var) |> Util.model

      refl = parent_model.__schema__(:association, field)
      unless refl do
        raise Ecto.QueryError, reason: "field `#{inspect parent_model}.#{field}` is not an association"
      end

      child_model = Util.find_source(sources, child_var) |> Util.model
      unless refl.associated == child_model do
        raise Ecto.QueryError, reason: "association on `#{inspect parent_model}.#{field}` " <>
          "doesn't match given model: `#{child_model}`"
      end

      unless child_model.__schema__(:primary_key) do
        raise Ecto.QueryError, reason: "`assoc/2` selector requires a primary key on " <>
          "model: `#{child_model}`"
      end

      expr = Util.source_expr(query, child_var)
      unless match?(%JoinExpr{qual: qual, assoc: assoc} when not nil?(assoc) and qual in [:inner, :left], expr) do
        raise Ecto.QueryError, reason: "can only associate on an inner or left association join"
      end

      assoc_select(child_var, nested_fields, state)
    end)
  end

  defp exprs_sources(exprs, sources) do
    Enum.map(exprs, fn(expr) ->
      Enum.map(expr.expr, fn({var, field}) ->
        source = Util.find_source(sources, var)
        {source, field}
      end)
    end) |> Enum.concat |> Enum.uniq
  end

  defp order_bys_sources(order_bys_expr, sources) do
    Enum.map(order_bys_expr, fn(expr) ->
      Enum.map(expr.expr, fn({_, var, field}) ->
        source = Util.find_source(sources, var)
        {source, field}
      end)
    end) |> Enum.concat |> Enum.uniq
  end

  defp check_grouped({source, field} = source_field, %{grouped?: grouped?, in_agg?: in_agg?, grouped: grouped}) do
    if grouped? and not in_agg? and not (source_field in grouped) do
      model = Util.model(source) || Util.source(source)
      raise Ecto.QueryError, reason: "`#{inspect model}.#{field}` must appear in `group_by` " <>
        "or be used in an aggregate function"
    end
  end

  defp new_state do
    %{sources: [], vars: [], grouped: [], grouped?: false,
      in_agg?: false, apis: nil, from: nil, query: nil}
  end
end
