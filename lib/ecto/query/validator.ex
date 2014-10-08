defmodule Ecto.Query.Validator do
  @moduledoc false

  # This module does validation on the query checking that it's in
  # a correct format, raising if it's not.

  # TODO: Check it raises on missing bindings

  alias Ecto.Query
  alias Ecto.Query.Util
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.JoinExpr
  alias Ecto.Associations.Assoc

  require Ecto.Query.Util

  def validate(query, apis, opts \\ []) do
    if query.from == nil do
      raise Ecto.QueryError, reason: "a query must have a from expression"
    end

    grouped = flatten(query.group_bys)
    grouped? = grouped?(query, apis)
    state = Map.merge(new_state,
                      %{sources: query.sources, grouped: grouped, grouped?: grouped?,
                        apis: apis, from: query.from, query: query})

    validate_joins(query, state)
    validate_wheres(query, state)
    validate_order_bys(query, state)
    validate_group_bys(query.group_bys, state)
    validate_havings(query, state)
    validate_preloads(query.preloads, state)
    validate_limit(query, state)
    validate_offset(query, state)

    unless opts[:skip_select] do
      validate_select(query, state)
      validate_distincts(query, state)
      preload_selected(query)
    end
  end

  def validate_update(query, apis, values, external) do
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
        state = Map.merge(new_state, %{sources: query.sources, apis: apis, external: external})
        type = check(expr, state)

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

  defp validate_joins(query, state) do
    state = %{state | grouped?: false}
    ons = Enum.map(query.joins, &(&1.on))
    validate_booleans(query, :join_on, ons, state)
  end

  defp validate_wheres(query, state) do
    state = %{state | grouped?: false}
    validate_booleans(query, :where, query.wheres, state)
  end

  defp validate_havings(query, state) do
    validate_booleans(query, :having, query.havings, state)
  end

  defp validate_limit(%Query{limit: nil}, _), do: :ok

  defp validate_limit(query, state) do
    if contains_variable?(query.limit.expr) do
      raise Ecto.QueryError, reason: "variables not allowed in limit expression"
    end

    validate_integer(query, :limit, query.limit, state)
  end

  defp validate_offset(%Query{offset: nil}, _), do: :ok

  defp validate_offset(query, state) do
    if contains_variable?(query.offset.expr) do
      raise Ecto.QueryError, reason: "variables not allowed in offset expression"
    end

    validate_integer(query, :offset, query.offset, state)
  end

  defp validate_expr_type(query, clause_type, valid_expr_type, expr, state) do
    rescue_metadata(clause_type, expr, fn ->
      state = %{state | external: expr.external}
      expr_type = catch_grouped(query, fn -> check(expr.expr, state) end)

      unless expr_type in [:unknown, valid_expr_type] do
        format_expr_type = Util.type_to_ast(expr_type) |> Macro.to_string
        raise Ecto.QueryError, reason: "#{clause_type} expression `#{Macro.to_string(expr.expr)}` " <>
          "is of type `#{format_expr_type}`, has to be of #{valid_expr_type} type"
      end
    end)
  end

  defp validate_integer(query, type, expr, state), do: validate_expr_type(query, type, :integer, expr, state)

  defp validate_booleans(query, type, query_exprs, state) do
    Enum.each(query_exprs, &(validate_expr_type(query, type, :boolean, &1, state)))
  end

  defp validate_order_bys(query, state) do
    Enum.each(query.order_bys, fn expr ->
      rescue_metadata(:order_by, expr, fn ->
        state = %{state | external: expr.external}
        Enum.each(expr.expr, fn {_dir, expr} ->
          catch_grouped(query, fn -> check(expr, state) end)
        end)
      end)
    end)
  end

  defp validate_group_bys(group_bys, state) do
    state = %{state | grouped?: false}
    Enum.each(group_bys, fn expr ->
      rescue_metadata(:group_by, expr, fn ->
        state = %{state | external: expr.external}
        Enum.each(expr.expr, &check(&1, state))
      end)
    end)
  end

  defp validate_preloads(preloads, %{from: from}) do
    model = Util.model(from)

    if preloads != [] and is_nil(model) do
      raise Ecto.QueryError, reason: "can only preload on fields from a model"
    end

    Enum.each(preloads, fn expr ->
      rescue_metadata(:preload, expr, fn ->
        check_preload_fields(expr.expr, model)
      end)
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

  defp validate_select(query, state) do
    rescue_metadata(:select, query.select, fn ->
      state = %{state | external: query.select.external}
      catch_grouped(query, fn -> select_clause(query.select.expr, state) end)
    end)
  end

  defp validate_distincts(query, state) do
    Enum.each(query.distincts, fn expr ->
      rescue_metadata(:distinct, expr, fn ->
        state = %{state | external: expr.external}
        Enum.each(expr.expr, fn expr ->
          catch_grouped(query, fn -> check(expr, state) end)
        end)
      end)
    end)

    # ensure that the fields in `distinct` appears before other fields in the `order_by` expression

    # ex: distinct: id, title / order_by: id, title => no error
    #     distinct: id, title / order_by: title, id => no error
    #     distinct: title / order_by: id => raise (title not in order_by)
    #     distinct: title / order_by: id, title => raise (title in order_by but not leftmost part)

    distincts =
      Enum.map(query.distincts, fn expr ->
        Enum.map(expr.expr, fn distinct ->
          {distinct, {expr.file, expr.line}}
        end)
      end) |> Enum.concat

    order_bys =
      Enum.map(query.order_bys, fn expr ->
        Enum.map(expr.expr, fn {_dir, expr} -> expr end)
      end) |> Enum.concat

    do_validate_distincts(distincts, order_bys)
  end

  defp do_validate_distincts([], _), do: :ok

  defp do_validate_distincts(_, []), do: :ok

  defp do_validate_distincts(distincts, [order_by_expr|order_bys]) do
    filter = fn {distinct_expr, _} ->
      equal?(distinct_expr, order_by_expr)
    end

    in_distinct? = Enum.any?(distincts, filter)

    if in_distinct? do
      distincts = Enum.reject(distincts, filter)
      do_validate_distincts(distincts, order_bys)
    else
      {_, {file, line}} = List.first(distincts)
      raise Ecto.QueryError, reason: "the `order_by` expression should first reference " <>
        "all the `distinct` fields before other fields", type: :distinct, file: file, line: line
    end
  end

  defp preload_selected(%Query{select: select, preloads: preloads}) do
    unless preloads == [] do
      rescue_metadata(:select, select, fn ->
        pos = Util.locate_var(select.expr, {:&, [], [0]})
        if is_nil(pos) do
          raise Ecto.QueryError, reason: "source in from expression " <>
            "needs to be selected when using preload query"
        end
      end)
    end
  end

  defp check(expr, state) do
    state = check_grouped(expr, state)
    type_check(expr, state)
  end

  # ^0 (references external data)
  defp type_check({:^, _, [ix]}, %{external: external}) do
    case Util.external_to_type Map.fetch!(external, ix) do
      {:ok, type} ->
        type
      {:error, reason} ->
        raise Ecto.QueryError, reason: reason
    end
  end

  # var.x
  defp type_check({{:., _, [{:&, _, [_]} = var, field]}, _, []} = expr, %{sources: sources} = state) do
    check_was_grouped(expr, state)
    source = Util.find_source(sources, var)

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

      Enum.each(fields, fn field ->
        field_expr = {{:., [], [var, field]}, [], []}
        state = check_grouped(field_expr, state)
        check_was_grouped(field_expr, state)
      end)

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

    # TODO: Check if aggregate function is allowed

    if is_agg and in_agg? do
      raise Ecto.QueryError, reason: "aggregate function calls cannot be nested"
    end

    state = %{state | in_agg?: is_agg}
    arg_types = Enum.map(args, &check(&1, state))

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

  # binary(...)
  defp type_check(%Ecto.Tagged{value: binary, type: :binary}, state) do
    if type_check(binary, state) in [:binary, :string, :any] do
      :binary
    else
      raise Ecto.QueryError, reason: "binary/1 argument has to be of binary type"
    end
  end

  # uuid(...)
  defp type_check(%Ecto.Tagged{value: binary, type: :uuid}, state) do
    if type_check(binary, state) in [:uuid, :string, :any] do
      :uuid
    else
      raise Ecto.QueryError, reason: "uuid/1 argument has to be of binary type"
    end
  end

  # array(..., type)
  defp type_check(%Ecto.Tagged{value: list, type: {:array, inner}}, state) do
    unless inner in Util.types do
      raise Ecto.QueryError, reason: "invalid type given to `array/2`: `#{inspect inner}`"
    end

    case external(list, state) do
      {:ok, list} when is_list(list) ->
        list = list
      {:ok, other} ->
        raise Ecto.QueryError, reason: "array/2 has to be given a list, given: `#{inspect other}`"
      :error ->
        :ok
    end

    unless is_nil(list) do
      elem_types = Enum.map(list, &type_check(&1, state))

      Enum.each(elem_types, fn type ->
        unless Util.type_eq?(inner, type) or Util.type_castable?(type, inner) do
          raise Ecto.QueryError, reason: "all elements in array have to be of same type"
        end
      end)
    end

    {:array, inner}
  end

  # values
  defp type_check(value, _state) do
    case Util.value_to_type(value) do
      {:ok, type} ->
        type
      {:error, reason} ->
        raise Ecto.QueryError, reason: reason
    end
  end

  defp external({:^, _, [ix]}, %{external: external}),
    do: {:ok, Map.fetch!(external, ix)}
  defp external(_other, _state),
    do: :error

  # Handle top level select cases

  defp select_clause({:assoc, _, [var, fields]}, state) do
    assoc_select(var, fields, state)
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
    check(other, state)
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

      case Util.source_expr(query, child_var) do
        %JoinExpr{qual: qual, assoc: assoc} when not is_nil(assoc) and qual in [:inner, :left] ->
          :ok
        %JoinExpr{} ->
          raise Ecto.QueryError, reason: "can only associate on an inner or left association join"
        _ ->
          :ok
      end

      assoc_select(child_var, nested_fields, state)
    end)
  end

  defp flatten(exprs) do
    Enum.flat_map(exprs, &(&1.expr))
  end

  defp grouped?(query, apis) do
    query.group_bys != [] or
    query.havings != [] or
    has_aggregate?(query.order_bys, apis) or
    has_aggregate?(query.distincts, apis) or
    has_aggregate?(query.select, apis)
  end

  defp has_aggregate?(%Ecto.Query.QueryExpr{expr: expr}, apis) do
    has_aggregate?(expr, apis)
  end

  defp has_aggregate?({left, right}, apis) do
    has_aggregate?(left, apis) or has_aggregate?(right, apis)
  end

  defp has_aggregate?({name, _, args}, apis) when is_atom(name) and is_list(args) do
    length_args = length(args)

    api = Enum.find(apis, &function_exported?(&1, name, length_args))
    agg? = api && api.aggregate?(name, length_args)

    !!agg? or Enum.any?(args, &has_aggregate?(&1, apis))
  end

  defp has_aggregate?({arg, _, args}, apis) when is_list(args) do
    has_aggregate?(arg, apis) or Enum.any?(args, &has_aggregate?(&1, apis))
  end

  defp has_aggregate?(list, apis) when is_list(list) do
    Enum.any?(list, &has_aggregate?(&1, apis))
  end

  defp has_aggregate?(_other, _apis) do
    false
  end

  defp contains_variable?({:&, _, _}),
    do: true
  defp contains_variable?({left, _, right}),
    do: contains_variable?(left) or contains_variable?(right)
  defp contains_variable?({left, right}),
    do: contains_variable?(left) or contains_variable?(right)
  defp contains_variable?(list) when is_list(list),
    do: Enum.any?(list, &contains_variable?/1)
  defp contains_variable?(_),
    do: false

  defp check_grouped(expr, %{grouped?: true, was_grouped?: false, in_agg?: false, grouped: grouped} = state) do
    if Enum.any?(grouped, &equal?(expr, &1)) do
      # TODO: If primary key was grouped on we can use all fields from
      #       that model
      %{state | was_grouped?: true}
    else
      state
    end
  end

  defp check_grouped(_expr, state) do
    state
  end

  defp check_was_grouped(expr, %{grouped?: true, was_grouped?: false, in_agg?: false}) do
    throw {:not_grouped, expr}
  end

  defp check_was_grouped(_expr, _state), do: :ok

  defp catch_grouped(query, fun) do
    try do
      fun.()
    catch
      :throw, {:not_grouped, expr} ->
        raise Ecto.QueryError, reason: "`#{Inspect.Ecto.Query.pp_from_query(query, expr)}` " <>
          "must appear in `group_by` or be used in an aggregate function"
    end
  end

  # Adds type, file and line metadata to the exception
  defp rescue_metadata(type, %QueryExpr{expr: expr, file: file, line: line}, fun) do
    try do
      fun.()
    rescue e in [Ecto.QueryError, Ecto.Query.TypeCheckError] ->
      stacktrace = System.stacktrace
      reraise %{e | type: type, query: expr, file: file, line: line}, stacktrace
    end
  end

  # Checks if two query expressions are equal
  defp equal?({func1, _, args1}, {func2, _, args2}),
    do: equal?(func1, func2) and equal?(args1, args2)

  defp equal?([arg1|list1], [arg2|list2]),
    do: equal?(arg1, arg2) and equal?(list1, list2)

  defp equal?([], []),
    do: true

  defp equal?(arg, arg),
    do: true

  defp equal?(_arg1, _arg2),
    do: false

  defp new_state do
    %{sources: [], vars: [], grouped: [], grouped?: false,
      was_grouped?: false, in_agg?: false, apis: nil, from: nil,
      query: nil, external: nil}
  end
end
