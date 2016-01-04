defmodule Ecto.Query.Planner do
  # Normalizes a query and its parameters.
  @moduledoc false

  alias Ecto.Query.SelectExpr
  alias Ecto.Query.JoinExpr

  if map_size(%Ecto.Query{}) != 17 do
    raise "Ecto.Query match out of date in builder"
  end

  @doc """
  Plans the query for execution.

  Planning happens in multiple steps:

    1. First the query is prepared by retrieving
       its cache key, casting and merging parameters

    2. Then a cache lookup is done, if the query is
       cached, we are done

    3. If there is no cache, we need to actually
       normalize and validate the query, asking the
       adapter to prepare it

    4. The query is sent to the adapter to be generated

  ## Cache

  All entries in the query, except the preload and sources
  field, should be part of the cache key.

  The cache value is the compiled query by the adapter
  along-side the select expression.
  """
  def query(query, operation, repo, adapter) do
    {query, params, key} = prepare(query, operation, adapter)
    if key == :nocache do
      {_, select, prepared} = query_without_cache(query, operation, adapter)
      {build_meta(query, select), prepared, params}
    else
      table = repo.__query_cache__
      case cache_lookup(repo, table, key) do
        [{_, select, prepared}] ->
          {build_meta(query, select), prepared, params}
        [] ->
          case query_without_cache(query, operation, adapter) do
            {:cache, select, prepared} ->
              :ets.insert(table, {key, select, prepared})
              {build_meta(query, select), prepared, params}
            {:nocache, select, prepared} ->
              {build_meta(query, select), prepared, params}
          end
      end
    end
  end

  defp cache_lookup(repo, table, key) do
    :ets.lookup(table, key)
  rescue
    ArgumentError ->
      raise ArgumentError,
        "repo #{inspect repo} is not started, please ensure it is part of your supervision tree"
  end

  defp query_without_cache(query, operation, adapter) do
    %{select: select} = query = normalize(query, operation, adapter)
    {cache, prepared} = adapter.prepare(operation, query)
    {cache, select && %{select | file: nil, line: nil}, prepared}
  end

  defp build_meta(%{prefix: prefix, sources: sources,
                    assocs: assocs, preloads: preloads}, select) do
    %{prefix: prefix, sources: sources,
      assocs: assocs, preloads: preloads, select: select}
  end

  @doc """
  Prepares the query for cache.

  This means all the parameters from query expressions are
  merged into a single value and their entries are prunned
  from the query.

  This function is called by the backend before invoking
  any cache mechanism.
  """
  def prepare(query, operation, adapter) do
    query
    |> prepare_sources
    |> prepare_assocs
    |> prepare_cache(operation, adapter)
  rescue
    e ->
      # Reraise errors so we ignore the planner inner stacktrace
      reraise e
  end

  @doc """
  Prepare the parameters by merging and casting them according to sources.
  """
  def prepare_cache(query, operation, adapter) do
    {query, {cache, params}} =
      traverse_exprs(query, operation, {[], []}, &{&3, merge_cache(&1, &2, &3, &4, adapter)})
    {query, Enum.reverse(params), finalize_cache(query, operation, cache)}
  end

  defp merge_cache(kind, query, expr, {cache, params}, adapter)
      when kind in ~w(select distinct limit offset)a do
    if expr do
      {params, cacheable?} = cast_and_merge_params(kind, query, expr, params, adapter)
      {merge_cache({kind, expr.expr}, cache, cacheable?), params}
    else
      {cache, params}
    end
  end

  defp merge_cache(kind, query, exprs, {cache, params}, adapter)
      when kind in ~w(where update group_by having order_by)a do
    {expr_cache, {params, cacheable?}} =
      Enum.map_reduce exprs, {params, true}, fn expr, {params, cacheable?} ->
        {params, current_cacheable?} = cast_and_merge_params(kind, query, expr, params, adapter)
        {expr.expr, {params, cacheable? and current_cacheable?}}
      end

    case expr_cache do
      [] -> {cache, params}
      _  -> {merge_cache({kind, expr_cache}, cache, cacheable?), params}
    end
  end

  defp merge_cache(:join, query, exprs, {cache, params}, adapter) do
    {expr_cache, {params, cacheable?}} =
      Enum.map_reduce exprs, {params, true}, fn
        %JoinExpr{on: on, qual: qual, source: source} = join, {params, cacheable?} ->
          {params, join_cacheable?} = cast_and_merge_params(:join, query, join, params, adapter)
          {params, on_cacheable?} = cast_and_merge_params(:join, query, on, params, adapter)
          {{qual, source_cache(source), on.expr},
           {params, cacheable? and join_cacheable? and on_cacheable?}}
      end

    case expr_cache do
      [] -> {cache, params}
      _  -> {merge_cache({:join, expr_cache}, cache, cacheable?), params}
    end
  end

  defp cast_and_merge_params(kind, query, expr, params, adapter) do
    Enum.reduce expr.params, {params, true}, fn
      {v, {:in_spread, type}}, {acc, _cacheable?} ->
        {unfold_in(cast_param(kind, query, expr, v, {:array, type}, adapter), acc), false}
      {v, type}, {acc, cacheable?} ->
        {[cast_param(kind, query, expr, v, type, adapter)|acc], cacheable?}
    end
  end

  defp merge_cache(_left, _right, false),  do: :nocache
  defp merge_cache(_left, :nocache, true), do: :nocache
  defp merge_cache(left, right, true),     do: [left|right]

  defp finalize_cache(_query, _operation, :nocache) do
    :nocache
  end

  defp finalize_cache(%{assocs: assocs, prefix: prefix, lock: lock, from: from,
                        select: select}, operation, cache) do
    cache =
      case select do
        %{take: take} when take != %{} ->
          [take: take] ++ cache
        _ ->
          cache
      end

    if assocs && assocs != [] do
      cache = [assocs: assocs] ++ cache
    end

    if prefix do
      cache = [prefix: prefix] ++ cache
    end

    if lock do
      cache = [lock: lock] ++ cache
    end

    [operation, source_cache(from)|cache]
  end

  defp source_cache({_, nil} = source), do: source
  defp source_cache({bin, model}), do: {bin, model, model.__schema__(:hash)}
  defp source_cache({:fragment, _, _} = source), do: source

  defp cast_param(kind, query, expr, v, type, adapter) do
    {model, field, type} = type_for_param!(kind, query, expr, type)
    cast = cast_param(kind, type, v)

    try do
      case cast do
        {:dump, type, v} ->
          case Ecto.Type.adapter_dump(adapter, type, v) do
            {:ok, v} -> v
            :error   -> error! query, expr, "cannot dump cast value `#{inspect v}` to type #{inspect type}"
          end
        {:error, error} ->
          error! query, expr, error
      end
    catch
      :error, %Ecto.QueryError{} = e when not is_nil(model) ->
        raise Ecto.CastError, schema: model, field: field, value: v, type: type,
                              message: Exception.message(e) <>
                                       "\nError when casting value to `#{inspect model}.#{field}`"
    end
  end

  defp cast_param(kind, {:in_array, {:array, type}}, value) do
    cast_param(kind, type, value)
  end

  defp cast_param(kind, {:in_array, :any}, value) do
    cast_param(kind, :any, value)
  end

  defp cast_param(kind, {:in_array, other}, value) do
    {:error, "value `#{inspect value}` in `#{kind}` expected to be part of an array " <>
             "but matched type is #{inspect other}"}
  end

  defp cast_param(kind, type, nil) when kind != :update do
    {:error, "value `nil` in `#{kind}` cannot be cast to type #{inspect type} " <>
             " (if you want to check for nils, use is_nil/1 instead)"}
  end

  defp cast_param(kind, type, v) do
    case Ecto.Type.cast(type, v) do
      {:ok, v} ->
        {:dump, type, v}
      :error ->
        {:error, "value `#{inspect v}` in `#{kind}` cannot be cast to type #{inspect type}"}
    end
  end

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

  defp prepare_joins([%JoinExpr{source: {source, model}} = join|t],
                     query, joins, sources, tail_sources, counter, offset) when is_atom(model) and model != nil do
    source = if is_binary(source), do: {source, model}, else: {model.__schema__(:source), model}
    join   = %{join | source: source, ix: counter}
    prepare_joins(t, query, [join|joins], [source|sources], tail_sources, counter + 1, offset)
  end

  defp prepare_joins([%JoinExpr{source: source} = join|t],
                     query, joins, sources, tail_sources, counter, offset) do
    join = %{join | source: source, ix: counter}
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

  defp prepare_assocs(query) do
    prepare_assocs(query, 0, query.assocs)
    query
  end

  defp prepare_assocs(query, ix, assocs) do
    # We validate the model exists when preparing joins above
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

      prepare_assocs(query, child_ix, child_assocs)
    end
  end

  defp find_source_expr(query, 0) do
    query.from
  end

  defp find_source_expr(query, ix) do
    Enum.find(query.joins, & &1.ix == ix)
  end

  @doc """
  Normalizes the query.

  After the query was prepared and there is no cache
  entry, we need to update its interpolations and check
  its fields and associations exist and are valid.
  """
  def normalize(query, operation, adapter) do
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
    |> traverse_exprs(operation, 0, &validate_and_increment(&1, &2, &3, &4, adapter))
    |> elem(0)
    |> normalize_select(operation)
  rescue
    e ->
      # Reraise errors so we ignore the planner inner stacktrace
      reraise e
  end

  defp validate_and_increment(kind, query, expr, counter, adapter)
      when kind in ~w(select distinct limit offset)a do
    if expr do
      validate_and_increment_each(kind, query, expr, counter, adapter)
    else
      {nil, counter}
    end
  end

  defp validate_and_increment(kind, query, exprs, counter, adapter)
      when kind in ~w(where group_by having order_by update)a do
    {exprs, counter} =
      Enum.reduce(exprs, {[], counter}, fn
        %{expr: []}, {list, acc} ->
          {list, acc}
        expr, {list, acc} ->
          {expr, acc} = validate_and_increment_each(kind, query, expr, acc, adapter)
          {[expr|list], acc}
      end)
    {Enum.reverse(exprs), counter}
  end

  defp validate_and_increment(:join, query, exprs, counter, adapter) do
    Enum.map_reduce exprs, counter, fn join, acc ->
      {source, acc} = validate_and_increment_each(:join, query, join, join.source, acc, adapter)
      {on, acc} = validate_and_increment_each(:join, query, join.on, acc, adapter)
      {%{join | on: on, source: source, params: nil}, acc}
    end
  end

  defp validate_and_increment_each(kind, query, expr, counter, adapter) do
    {inner, acc} = validate_and_increment_each(kind, query, expr, expr.expr, counter, adapter)
    {%{expr | expr: inner, params: nil}, acc}
  end

  defp validate_and_increment_each(kind, query, expr, ast, counter, adapter) do
    Macro.prewalk ast, counter, fn
      {:in, in_meta, [left, {:^, meta, [param]}]}, acc ->
        {right, acc} = validate_in(meta, expr, param, acc)
        {{:in, in_meta, [left, right]}, acc}

      {:^, meta, [ix]}, acc when is_integer(ix) ->
        {{:^, meta, [acc]}, acc + 1}

      {{:., _, [{:&, _, [source]}, field]} = dot, meta, []}, acc ->
        type = type!(kind, query, expr, source, field)
        {{dot, [ecto_type: type] ++ meta, []}, acc}

      {:type, _, [{:^, meta, [ix]}, _expr]}, acc when is_integer(ix) ->
        {_, t} = Enum.fetch!(expr.params, ix)
        {_, _, type} = type_for_param!(kind, query, expr, t)
        {%Ecto.Query.Tagged{value: {:^, meta, [acc]}, tag: type,
                            type: Ecto.Type.type(type)}, acc + 1}

      %Ecto.Query.Tagged{value: v, type: type}, acc ->
        {cast_param(kind, query, expr, v, type, adapter), acc}

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

  defp normalize_select(query, operation) when operation in [:update_all, :delete_all] do
    query
  end
  defp normalize_select(%{select: nil} = query, _operation) do
    select = %SelectExpr{expr: {:&, [], [0]}, line: __ENV__.line, file: __ENV__.file}
    %{query | select: normalize_fields(query, select)}
  end
  defp normalize_select(%{select: select} = query, _operation) do
    %{query | select: normalize_fields(query, select)}
  end

  defp normalize_fields(%{assocs: [], preloads: [], sources: sources},
                        %{take: take, expr: expr} = select) do
    {fields, from} = collect_fields(expr, sources, take, :error)

    fields =
      case from do
        {:ok, from} -> [{:&, [], [0, from]}|fields]
        :error -> fields
      end

    %{select | fields: fields}
  end

  defp normalize_fields(%{assocs: assocs, sources: sources} = query,
                        %{take: take, expr: expr} = select) do
    {fields, from} = collect_fields(expr, sources, take, :error)

    case from do
      {:ok, from} ->
        assocs = collect_assocs(sources, assocs)
        fields = [{:&, [], [0, from]}|assocs] ++ fields
        %{select | fields: fields}
      :error ->
        error! query, "the binding used in `from` must be selected in `select` when using `preload`"
    end
  end

  defp collect_fields({:&, _, [0]}, sources, take, :error) do
    fields =
      case Map.fetch(take, 0) do
        {:ok, value} -> value
        :error -> fields!(sources, 0)
      end
    {[], {:ok, fields}}
  end
  defp collect_fields({:&, _, [0]}, _sources, _take, from) do
    {[], from}
  end
  defp collect_fields({:&, _, [ix]}, sources, take, from) do
    fields =
      case Map.fetch(take, ix) do
        {:ok, value} -> value
        :error -> fields!(sources, ix)
      end
    {[{:&, [], [ix, fields]}], from}
  end

  defp collect_fields({left, right}, sources, take, from) do
    {left, from}  = collect_fields(left, sources, take, from)
    {right, from} = collect_fields(right, sources, take, from)
    {left ++ right, from}
  end
  defp collect_fields({:{}, _, elems}, sources, take, from),
    do: collect_fields(elems, sources, take, from)
  defp collect_fields({:%{}, _, pairs}, sources, take, from),
    do: collect_fields(pairs, sources, take, from)
  defp collect_fields(list, sources, take, from) when is_list(list),
    do: Enum.flat_map_reduce(list, from, &collect_fields(&1, sources, take, &2))
  defp collect_fields(expr, _sources, _take, from) when is_atom(expr) or is_binary(expr) or is_number(expr),
    do: {[], from}
  defp collect_fields(expr, _sources, _take, from),
    do: {[expr], from}

  defp collect_assocs(sources, [{_assoc, {ix, children}}|tail]) do
    [{:&, [], [ix, fields!(sources, ix)]}] ++
      collect_assocs(sources, children) ++
      collect_assocs(sources, tail)
  end
  defp collect_assocs(_sources, []) do
    []
  end

  defp fields!(sources, ix) do
    case elem(sources, ix) do
      {_, nil} -> nil
      {_, schema} -> schema.__schema__(:fields)
    end
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

  defp type!(kind, query, expr, source, field) when is_integer(source) do
    case elem(query.sources, source) do
      {_, model} -> type!(kind, query, expr, model, field)
      {:fragment, _, _} -> :any
    end
  end

  defp type!(kind, query, expr, model, field) when is_atom(model) do
    if type = model.__schema__(:type, field) do
      type
    else
      error! query, expr, "field `#{inspect model}.#{field}` in `#{kind}` " <>
                          "does not exist in the schema"
    end
  end

  defp type_for_param!(kind, query, expr, {composite, {ix, field}}) when is_integer(ix) do
    {_, model} = elem(query.sources, ix)
    {model, field, {composite, type!(kind, query, expr, model, field)}}
  end

  defp type_for_param!(kind, query, expr, {ix, field}) when is_integer(ix) do
    {_, model} = elem(query.sources, ix)
    {model, field, type!(kind, query, expr, model, field)}
  end

  defp type_for_param!(_kind, _query, _expr, type) do
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

  defp reraise(exception) do
    reraise exception, Enum.reject(System.stacktrace, &match?({__MODULE__, _, _, _}, &1))
  end

  defp error!(query, message) do
    raise Ecto.QueryError, message: message, query: query
  end

  defp error!(query, expr, message) do
    raise Ecto.QueryError, message: message, query: query, file: expr.file, line: expr.line
  end
end
