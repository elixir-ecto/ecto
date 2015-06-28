defmodule Ecto.Query.Planner do
  # Normalizes a query and its parameters.
  @moduledoc false

  alias Ecto.Query.SelectExpr
  alias Ecto.Query.JoinExpr

  if map_size(%Ecto.Query{}) != 16 do
    raise "Ecto.Query match out of date in builder"
  end

  @doc """
  Validates and cast the given fields belonging to the given model.
  """
  def fields(model, kind, kw, id_types) do
    types = model.__changeset__

    for {field, value} <- kw do
      type = Ecto.Type.normalize Map.get(types, field), id_types

      unless type do
        raise Ecto.ChangeError,
          message: "field `#{inspect model}.#{field}` in `#{kind}` does not exist in the model source"
      end

      case Ecto.Type.dump(type, value) do
        {:ok, value} ->
          {field, value}
        :error ->
          raise Ecto.ChangeError,
            message: "value `#{inspect value}` for `#{inspect model}.#{field}` " <>
                     "in `#{kind}` does not match type #{inspect type}"
      end
    end
  end

  @doc """
  Plans the query for execution.

  Planning happens in multiple steps:

    1. First the query is prepared by retrieving
       its cache key, casting and merging parameters

    2. Then a cache lookup is done, if the query is
       cached, we are done

    3. If there is no cache, we need to actually
       normalize and validate the query, before sending
       it to the adapter

    4. The query is sent to the adapter to be generated

  Currently only steps 1 and 3 are implemented.

  ## Cache

  All entries in the query, except the preload and sources
  field, should be part of the cache key.

  The cache value is the compiled query by the adapter
  along-side the select expression.
  """
  def query(query, operation, base, id_types) do
    {query, params} = prepare(query, operation, base, id_types)
    {normalize(query, operation, base), params}
  end

  @doc """
  Prepares the query for cache.

  This means all the parameters from query expressions are
  merged into a single value and their entries are prunned
  from the query.

  This function is called by the backend before invoking
  any cache mechanism.
  """
  def prepare(query, operation, params, id_types) do
    query
    |> prepare_sources
    |> prepare_params(operation, params, id_types)
  rescue
    e ->
      # Reraise errors so we ignore the planner inner stacktrace
      raise e
  end

  @doc """
  Prepare the parameters by merging and casting them according to sources.
  """
  def prepare_params(query, operation, base, id_types) do
    {query, params} = traverse_exprs(query, operation, [], &{&3, merge_params(&1, &2, &3, &4, id_types)})
    {query, base ++ Enum.reverse(params)}
  end

  defp merge_params(kind, query, expr, params, id_types)
      when kind in ~w(select distinct limit offset)a do
    if expr do
      cast_and_merge_params(kind, query, expr, params, id_types)
    else
      params
    end
  end

  defp merge_params(kind, query, exprs, acc, id_types)
      when kind in ~w(where update group_by having order_by)a do
    Enum.reduce exprs, acc, fn expr, params ->
      cast_and_merge_params(kind, query, expr, params, id_types)
    end
  end

  defp merge_params(:join, query, exprs, acc, id_types) do
    Enum.reduce exprs, acc, fn %JoinExpr{on: on}, params ->
      cast_and_merge_params(:join, query, on, params, id_types)
    end
  end

  defp cast_and_merge_params(kind, query, expr, params, id_types) do
    Enum.reduce expr.params, params, fn
      {v, {:in, type}}, acc ->
        unfold_in(cast_param(kind, query, expr, v, {:array, type}, id_types), acc)
      {v, type}, acc ->
        [cast_param(kind, query, expr, v, type, id_types)|acc]
    end
  end

  defp cast_param(kind, query, expr, v, type, id_types) do
    {model, field, type} = type_from_param!(kind, query, expr, type)
    type = Ecto.Type.normalize(type, id_types)

    case cast_param(kind, type, v) do
      {:ok, v} ->
        Ecto.Type.dump!(type, v)
      {:match, type} ->
        Ecto.Type.dump!(type, v)
      :error ->
        try do
          error! query, expr, "value `#{inspect v}` in `#{kind}` cannot be cast to " <>
                              "type #{inspect type}" <> maybe_nil(v)
        catch
          :error, %Ecto.QueryError{} = e when not is_nil(model) ->
            raise Ecto.CastError, model: model, field: field, value: v, type: type,
                                  message: Exception.message(e) <>
                                           "\nError when casting value to `#{inspect model}.#{field}`"
        end
    end
  end

  defp cast_param(kind, _type, nil) when kind != :update do
    :error
  end

  defp cast_param(_kind, type, v) do
    # If the type is a primitive type and we are giving it
    # a struct, we first check if the struct type and the
    # given type are match and, if so, use the struct type
    # when dumping.
    if Ecto.Type.primitive?(type) &&
       (struct = param_struct(v)) &&
       Ecto.Type.match?(struct.type, type) do
      {:match, struct}
    else
      Ecto.Type.cast(type, v)
    end
  end

  defp maybe_nil(nil), do: " (if you want to check for nils, use is_nil/1 instead)"
  defp maybe_nil(_),   do: ""

  defp param_struct(%{__struct__: struct}) when not struct in [Decimal] do
    struct
  end
  defp param_struct(_), do: nil

  defp unfold_in(%Ecto.Query.Tagged{value: value, type: {:array, type}}, acc),
    do: unfold_in(value, type, acc)
  defp unfold_in(value, acc) when is_list(value),
    do: Enum.reverse(value, acc)

  defp unfold_in([h|t], type, acc),
    do: unfold_in(t, type, [%Ecto.Query.Tagged{value: h, type: type}|acc])
  defp unfold_in([], _type, acc),
    do: acc

  @doc """
  Prepare all sources, by traversing and expanding joins.
  """
  def prepare_sources(query) do
    from = query.from || error!(query, "query must have a from expression")
    {joins, sources, tail_sources} = prepare_joins(query, [from], length(query.joins))
    %{query | sources: (tail_sources ++ sources) |> Enum.reverse |> List.to_tuple(),
              joins: joins |> Enum.reverse}
  end

  defp prepare_joins(query, sources, offset) do
    prepare_joins(query.joins, query, [], sources, [], 1, offset)
  end

  defp prepare_joins([%JoinExpr{assoc: {ix, assoc}, qual: qual} = join|t],
                     query, joins, sources, tail_sources, counter, offset) do
    {source, model} = Enum.fetch!(Enum.reverse(sources), ix)

    unless model do
      error! query, join, "cannot perform association join on #{inspect source} " <>
                          "because it does not have a model"
    end

    refl = model.__schema__(:association, assoc)

    unless refl do
      error! query, join, "could not find association `#{assoc}` on model #{inspect model}"
    end

    # If we have the following join:
    #
    #     from p in Post,
    #       join: p in assoc(p, :comments)
    #
    # The callback below will return a query that contains only
    # joins in a way it starts with the Post and ends in the
    # Comment.
    #
    # This means we need to rewrite the joins below to properly
    # shift the &... identifier in a way that:
    #
    #    &0         -> becomes assoc ix
    #    &LAST_JOIN -> becomes counter
    #
    # All values in the middle should be shifted by offset,
    # all values after join are already correct.
    child = refl.__struct__.joins_query(refl)
    last_ix = length(child.joins)
    source_ix = counter

    {child_joins, child_sources, child_tail} =
      prepare_joins(child, [child.from], offset + last_ix - 1)

    # Rewrite joins indexes as mentioned above
    child_joins = Enum.map(child_joins, &rewrite_join(&1, qual, ix, last_ix, source_ix, offset))

    # Drop the last resource which is the association owner (it is reversed)
    child_sources = Enum.drop(child_sources, -1)

    [current_source|child_sources] = child_sources
    child_sources = child_tail ++ child_sources

    prepare_joins(t, query, child_joins ++ joins, [current_source|sources],
                  child_sources ++ tail_sources, counter + 1, offset + length(child_sources))
  end

  defp prepare_joins([%JoinExpr{source: {source, nil}} = join|t],
                     query, joins, sources, tail_sources, counter, offset) when is_binary(source) do
    source = {source, nil}
    join   = %{join | source: source, ix: counter}
    prepare_joins(t, query, [join|joins], [source|sources], tail_sources, counter + 1, offset)
  end

  defp prepare_joins([%JoinExpr{source: {source, model}} = join|t],
                     query, joins, sources, tail_sources, counter, offset) when is_atom(model) do
    source = if is_binary(source), do: {source, model}, else: {model.__schema__(:source), model}
    join   = %{join | source: source, ix: counter}
    prepare_joins(t, query, [join|joins], [source|sources], tail_sources, counter + 1, offset)
  end

  defp prepare_joins([], _query, joins, sources, tail_sources, _counter, _offset) do
    {joins, sources, tail_sources}
  end

  defp rewrite_join(%{on: on, ix: join_ix} = join, qual, ix, last_ix, source_ix, inc_ix) do
    on = update_in on.expr, fn expr ->
      Macro.prewalk expr, fn
        {:&, meta, [join_ix]} ->
          {:&, meta, [rewrite_ix(join_ix, ix, last_ix, source_ix, inc_ix)]}
        other ->
          other
      end
    end

    %{join | on: on, qual: qual,
             ix: rewrite_ix(join_ix, ix, last_ix, source_ix, inc_ix)}
  end

  # We need to replace the source by the one from the assoc
  defp rewrite_ix(0, ix, _last_ix, _source_ix, _inc_x), do: ix

  # The last entry will have the current source index
  defp rewrite_ix(last_ix, _ix, last_ix, source_ix, _inc_x), do: source_ix

  # All above last are already correct
  defp rewrite_ix(join_ix, _ix, last_ix, _source_ix, _inc_ix) when join_ix > last_ix, do: join_ix

  # All others need to be incremented by the offset sources
  defp rewrite_ix(join_ix, _ix, _last_ix, _source_ix, inc_ix), do: join_ix + inc_ix

  @doc """
  Normalizes the query.

  After the query was prepared and there is no cache
  entry, we need to update its interpolations and check
  its fields and associations exist and are valid.
  """
  def normalize(query, operation, base) do
    case operation do
      :all ->
        assert_no_update!(query, operation)
      :update_all ->
        assert_update!(query, operation)
        assert_only_filter_expressions!(query, operation)
      :delete_all ->
        assert_no_update!(query, operation)
        assert_only_filter_expressions!(query, operation)
    end

    query
    |> traverse_exprs(operation, length(base), &validate_and_increment/4)
    |> elem(0)
    |> normalize_select(operation)
    |> validate_assocs
  rescue
    e ->
      # Reraise errors so we ignore the planner inner stacktrace
      raise e
  end

  defp validate_and_increment(kind, query, expr, counter)
      when kind in ~w(select distinct limit offset)a do
    if expr do
      validate_and_increment_each(kind, query, expr, counter)
    else
      {nil, counter}
    end
  end

  defp validate_and_increment(kind, query, exprs, counter)
      when kind in ~w(where group_by having order_by update)a do
    Enum.map_reduce exprs, counter, &validate_and_increment_each(kind, query, &1, &2)
  end

  defp validate_and_increment(:join, query, exprs, counter) do
    Enum.map_reduce exprs, counter, fn join, acc ->
      {on, acc} = validate_and_increment_each(:join, query, join.on, acc)
      {%{join | on: on}, acc}
    end
  end

  defp validate_and_increment_each(kind, query, expr, counter) do
    {inner, acc} = validate_and_increment_each(kind, query, expr, expr.expr, counter)
    {%{expr | expr: inner, params: nil}, acc}
  end

  defp validate_and_increment_each(kind, query, expr, ast, counter) do
    Macro.prewalk ast, counter, fn
      {:in, in_meta, [left, {:^, meta, [param]}]}, acc ->
        {right, acc} = validate_in(meta, expr, param, acc)
        {{:in, in_meta, [left, right]}, acc}

      {:^, meta, [ix]}, acc when is_integer(ix) ->
        {{:^, meta, [acc]}, acc + 1}

      {{:., _, [{:&, _, [source]}, field]} = dot, meta, []}, acc ->
        type = validate_field(kind, query, expr, source, field, meta)
        {{dot, [ecto_type: type] ++ meta, []}, acc}

      {:type, _, [{:^, _, [param]} = v, _expr]}, acc ->
        {_, t} = Enum.fetch!(expr.params, param)
        {_, _, type} = type_from_param!(kind, query, expr, t)
        {%Ecto.Query.Tagged{value: v, type: Ecto.Type.type(type), tag: type}, acc}

      other, acc ->
        {other, acc}
    end
  end

  defp validate_in(meta, expr, param, acc) do
    {v, _t} = Enum.fetch!(expr.params, param)
    length  = length(v)

    case length do
      0 -> {[], acc}
      _ -> {{:^, meta, [acc, length]}, acc + length}
    end
  end

  defp validate_field(kind, query, expr, source, field, meta) do
    {_, model} = elem(query.sources, source)

    if model do
      type = type!(kind, query, expr, model, field)

      if (expected = Keyword.get(meta, :ecto_type)) &&
         !Ecto.Type.match?(type, expected) do
        error! query, expr, "field `#{inspect model}.#{field}` in `#{kind}` does not type check. " <>
                            "It has type #{inspect type} but a type #{inspect expected} is expected"
      end

      type
    end
  end

  defp normalize_select(query, operation) do
    cond do
      operation in [:update_all, :delete_all] ->
        query
      select = query.select ->
        %{query | select: normalize_fields(query, select)}
      true ->
        select = %SelectExpr{expr: {:&, [], [0]}}
        %{query | select: normalize_fields(query, select)}
    end
  end

  defp normalize_fields(%{assocs: [], preloads: []} = query, select) do
    {fields, from?} = collect_fields(query, select.expr, false)

    fields =
      if from? do
        [{:&, [], [0]}|fields]
      else
        fields
      end

    %{select | fields: fields}
  end

  defp normalize_fields(%{assocs: assocs} = query, select) do
    {fields, from?} = collect_fields(query, select.expr, false)

    unless from? do
      error! query, "the binding used in `from` must be selected in `select` when using `preload`"
    end

    assocs = collect_assocs(assocs)
    fields = [{:&, [], [0]}|assocs] ++ fields
    %{select | fields: fields}
  end

  defp collect_fields(_query, {:&, _, [ix]} = expr, from?) do
    if ix == 0 do
      {[], true}
    else
      {[expr], from?}
    end
  end

  defp collect_fields(query, {left, right}, from?),
    do: collect_fields(query, [left, right], from?)
  defp collect_fields(query, {:{}, _, elems}, from?),
    do: collect_fields(query, elems, from?)
  defp collect_fields(query, {:%{}, _, pairs}, from?),
    do: collect_fields(query, Enum.map(pairs, &elem(&1, 1)), from?)
  defp collect_fields(query, list, from?) when is_list(list),
    do: Enum.flat_map_reduce(list, from?, &collect_fields(query, &1, &2))
  defp collect_fields(_query, expr, from?),
    do: {[expr], from?}

  defp collect_assocs([{_assoc, {ix, children}}|tail]),
    do: [{:&, [], [ix]}] ++ collect_assocs(children) ++ collect_assocs(tail)
  defp collect_assocs([]),
    do: []

  defp validate_assocs(query) do
    validate_assocs(query, 0, query.assocs)
    query
  end

  defp validate_assocs(query, ix, assocs) do
    # We validate the model exists when normalizing fields above
    {_, parent_model} = elem(query.sources, ix)

    Enum.each assocs, fn {assoc, {child_ix, child_assocs}} ->
      refl = parent_model.__schema__(:association, assoc)

      unless refl do
        error! query, "field `#{inspect parent_model}.#{assoc}` " <>
                      "in preload is not an association"
      end

      case find_source_expr(query, child_ix) do
        %JoinExpr{qual: qual} when qual in [:inner, :left] ->
          :ok
        %JoinExpr{qual: qual} ->
          error! query, "association `#{inspect parent_model}.#{assoc}` " <>
                        "in preload requires an inner or left join, got #{qual} join"
        _ ->
          :ok
      end

      validate_assocs(query, child_ix, child_assocs)
    end
  end

  defp find_source_expr(query, 0) do
    query.from
  end

  defp find_source_expr(query, ix) do
    Enum.find(query.joins, & &1.ix == ix)
  end

  ## Helpers

  # Traverse all query components with expressions.
  # Therefore from, preload, assocs and lock are not traversed.
  defp traverse_exprs(original, operation, acc, fun) do
    query = original

    if operation == :update_all do
      {updates, acc} = fun.(:update, original, original.updates, acc)
      query = %{query | updates: updates}
    end

    {select, acc} = fun.(:select, original, original.select, acc)
    query = %{query | select: select}

    {distinct, acc} = fun.(:distinct, original, original.distinct, acc)
    query = %{query | distinct: distinct}

    {joins, acc} = fun.(:join, original, original.joins, acc)
    query = %{query | joins: joins}

    {wheres, acc} = fun.(:where, original, original.wheres, acc)
    query = %{query | wheres: wheres}

    {group_bys, acc} = fun.(:group_by, original, original.group_bys, acc)
    query = %{query | group_bys: group_bys}

    {havings, acc} = fun.(:having, original, original.havings, acc)
    query = %{query | havings: havings}

    {order_bys, acc} = fun.(:order_by, original, original.order_bys, acc)
    query = %{query | order_bys: order_bys}

    {limit, acc} = fun.(:limit, original, original.limit, acc)
    query = %{query | limit: limit}

    {offset, acc} = fun.(:offset, original, original.offset, acc)
    {%{query | offset: offset}, acc}
  end

  defp type!(_kind, _query, _expr, nil, _field), do: :any

  defp type!(kind, query, expr, model, field) do
    if type = model.__schema__(:field, field) do
      type
    else
      error! query, expr, "field `#{inspect model}.#{field}` in `#{kind}` " <>
                          "does not exist in the model source"
    end
  end

  defp type_from_param!(kind, query, expr, {composite, {ix, field}}) when is_integer(ix) do
    {_, model} = elem(query.sources, ix)
    {model, field, {composite, type!(kind, query, expr, model, field)}}
  end

  defp type_from_param!(kind, query, expr, {ix, field}) when is_integer(ix) do
    {_, model} = elem(query.sources, ix)
    {model, field, type!(kind, query, expr, model, field)}
  end

  defp type_from_param!(_kind, _query, _expr, type) do
    {nil, nil, type}
  end

  defp assert_update!(%Ecto.Query{updates: updates} = query, operation) do
    changes =
      Enum.reduce(updates, %{}, fn update, acc ->
        Enum.reduce(update.expr, acc, fn {_op, kw}, acc ->
          Enum.reduce(kw, acc, fn {k, v}, acc ->
            Map.update(acc, k, v, fn _ ->
              error! query, "duplicate field `#{k}` for `#{operation}`"
            end)
          end)
        end)
      end)

    if changes == %{} do
      error! query, "`#{operation}` requires at least one field to be updated"
    end
  end

  defp assert_no_update!(query, operation) do
    case query do
      %Ecto.Query{updates: []} -> query
      _ ->
        error! query, "`#{operation}` does not allow `update` expressions"
    end
  end

  defp assert_only_filter_expressions!(query, operation) do
    case query do
      %Ecto.Query{select: nil, order_bys: [], limit: nil, offset: nil,
                  group_bys: [], havings: [], preloads: [], assocs: [],
                  distinct: nil, lock: nil} ->
        query
      _ ->
        error! query, "`#{operation}` allows only `where` and `join` expressions"
    end
  end

  defp error!(query, message) do
    raise Ecto.QueryError, message: message, query: query
  end

  defp error!(query, expr, message) do
    raise Ecto.QueryError, message: message, query: query, file: expr.file, line: expr.line
  end
end
