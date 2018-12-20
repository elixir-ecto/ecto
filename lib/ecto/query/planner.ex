defmodule Ecto.Query.Planner do
  # Normalizes a query and its parameters.
  @moduledoc false

  alias Ecto.Query.{BooleanExpr, DynamicExpr, JoinExpr, QueryExpr, SelectExpr}

  if map_size(%Ecto.Query{}) != 20 do
    raise "Ecto.Query match out of date in builder"
  end

  @doc """
  Converts a query to a list of joins.

  The from is moved as last join with the where conditions as its "on"
  in order to keep proper binding order.
  """
  def query_to_joins(qual, source, %{wheres: wheres, joins: joins}, position) do
    on = %QueryExpr{file: __ENV__.file, line: __ENV__.line, expr: true, params: []}

    on =
      Enum.reduce(wheres, on, fn %BooleanExpr{op: op, expr: expr, params: params}, acc ->
        merge_expr_and_params(op, acc, expr, params)
      end)

    join = %JoinExpr{qual: qual, source: source, file: __ENV__.file, line: __ENV__.line, on: on}
    last = length(joins) + position

    mapping = fn
      0  -> last
      ix -> ix + position - 1
    end

    for {%{on: on} = join, ix} <- Enum.with_index(joins ++ [join]) do
      %{join | on: rewrite_sources(on, mapping), ix: ix + position}
    end
  end

  defp merge_expr_and_params(op, %QueryExpr{expr: left_expr, params: left_params} = struct,
                             right_expr, right_params) do
    right_expr =
      case length(left_params) do
        0 ->
          right_expr
        prefix ->
          Macro.prewalk(right_expr, fn
            {:^, meta, [counter]} when is_integer(counter) -> {:^, meta, [prefix + counter]}
            other -> other
          end)
      end

    %{struct | expr: merge_expr(op, left_expr, right_expr), params: left_params ++ right_params}
  end

  defp merge_expr(_op, left, true), do: left
  defp merge_expr(_op, true, right), do: right
  defp merge_expr(op, left, right), do: {op, [], [left, right]}

  @doc """
  Rewrites the given query expression sources using the given mapping.
  """
  def rewrite_sources(%{expr: expr, params: params} = part, mapping) do
    expr =
      Macro.prewalk expr, fn
        %Ecto.Query.Tagged{type: type, tag: tag} = tagged ->
          %{tagged | type: rewrite_type(type, mapping), tag: rewrite_type(tag, mapping)}
        {:&, meta, [ix]} ->
          {:&, meta, [mapping.(ix)]}
        other ->
          other
      end

    params =
      Enum.map params, fn
        {val, type} ->
          {val, rewrite_type(type, mapping)}
        val ->
          val
      end

    %{part | expr: expr, params: params}
  end

  defp rewrite_type({composite, {ix, field}}, mapping) when is_integer(ix) do
    {composite, {mapping.(ix), field}}
  end

  defp rewrite_type({ix, field}, mapping) when is_integer(ix) do
    {mapping.(ix), field}
  end

  defp rewrite_type(other, _mapping) do
    other
  end

  @doc """
  Define the query cache table.
  """
  def new_query_cache(name) do
    :ets.new(name, [:set, :public, read_concurrency: true])
  end

  @doc """
  Plans the query for execution.

  Planning happens in multiple steps:

    1. First the query is planned by retrieving
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
  def query(query, operation, cache, adapter, counter) do
    {query, params, key} = plan(query, operation, adapter, counter)
    query_with_cache(key, query, operation, cache, adapter, counter, params)
  end

  defp query_with_cache(key, query, operation, cache, adapter, counter, params) do
    case query_lookup(key, query, operation, cache, adapter, counter) do
      {_, select, prepared} ->
        {build_meta(query, select), {:nocache, prepared}, params}
      {_key, :cached, select, cached} ->
        update = &cache_update(cache, key, &1)
        reset = &cache_reset(cache, key, &1)
        {build_meta(query, select), {:cached, update, reset, cached}, params}
      {_key, :cache, select, prepared} ->
        update = &cache_update(cache, key, &1)
        {build_meta(query, select), {:cache, update, prepared}, params}
    end
  end

  defp query_lookup(:nocache, query, operation, _cache, adapter, counter) do
    query_without_cache(query, operation, adapter, counter)
  end

  defp query_lookup(key, query, operation, cache, adapter, counter) do
    case :ets.lookup(cache, key) do
      [term] -> term
      [] -> query_prepare(query, operation, adapter, counter, cache, key)
    end
  end

  defp query_prepare(query, operation, adapter, counter, cache, key) do
    case query_without_cache(query, operation, adapter, counter) do
      {:cache, select, prepared} ->
        cache_insert(cache, key, {key, :cache, select, prepared})
      {:nocache, _, _} = nocache ->
        nocache
    end
  end

  defp cache_insert(cache, key, elem) do
    case :ets.insert_new(cache, elem) do
      true ->
        elem
      false ->
        [elem] = :ets.lookup(cache, key)
        elem
    end
  end

  defp cache_update(cache, key, cached) do
    _ = :ets.update_element(cache, key, [{2, :cached}, {4, cached}])
    :ok
  end

  defp cache_reset(cache, key, prepared) do
    _ = :ets.update_element(cache, key, [{2, :cache}, {4, prepared}])
    :ok
  end

  defp query_without_cache(query, operation, adapter, counter) do
    {query, select} = normalize(query, operation, adapter, counter)
    {cache, prepared} = adapter.prepare(operation, query)
    {cache, select, prepared}
  end

  defp build_meta(%{sources: sources, preloads: preloads}, select) do
    %{select: select, preloads: preloads, sources: sources}
  end

  @doc """
  Prepares the query for cache.

  This means all the parameters from query expressions are
  merged into a single value and their entries are pruned
  from the query.

  This function is called by the backend before invoking
  any cache mechanism.
  """
  def plan(query, operation, adapter, counter) do
    query
    |> plan_sources(adapter)
    |> plan_assocs
    |> plan_combinations(operation, adapter, counter)
    |> plan_cache(operation, adapter, counter)
  rescue
    e ->
      # Reraise errors so we ignore the planner inner stacktrace
      filter_and_reraise e, System.stacktrace
  end

  @doc """
  Prepare all sources, by traversing and expanding joins.
  """
  def plan_sources(query, adapter) do
    {from, sources} = plan_from(query, adapter)
    {joins, sources, tail_sources} = plan_joins(query, sources, length(query.joins), adapter)
    %{query | from: from, joins: joins |> Enum.reverse,
              sources: (tail_sources ++ sources) |> Enum.reverse |> List.to_tuple()}
  end

  defp plan_from(%{from: nil} = query, _adapter) do
    error!(query, "query must have a from expression")
  end

  defp plan_from(%{from: from} = query, adapter) do
    {from, source} = plan_source(query, from, adapter)
    {from, [source]}
  end

  defp plan_source(query, %{source: %Ecto.SubQuery{} = subquery} = expr, adapter) do
    try do
      %{query: inner_query} = subquery
      {inner_query, params, key} = plan(inner_query, :all, adapter, 0)
      assert_no_subquery_assocs!(inner_query)
      {inner_query, select} = inner_query |> ensure_select(true) |> subquery_select(adapter)
      subquery = %{subquery | query: inner_query, params: params, cache: key, select: select}
      {%{expr | source: subquery}, subquery}
    rescue
      e -> raise Ecto.SubQueryError, query: query, exception: e
    end
  end

  defp plan_source(query, %{source: {nil, schema}, prefix: prefix} = expr, _adapter)
       when is_atom(schema) and schema != nil do
    source = schema.__schema__(:source)
    {%{expr | source: {source, schema}}, {source, schema, prefix || query.prefix}}
  end

  defp plan_source(query, %{source: {source, schema}, prefix: prefix} = expr, _adapter)
       when is_binary(source) and is_atom(schema),
       do: {expr, {source, schema, prefix || query.prefix}}

  defp plan_source(_query, %{source: {:fragment, _, _} = source} = expr, _adapter),
       do: {expr, source}

  defp assert_no_subquery_assocs!(%{assocs: assocs, preloads: preloads} = query)
       when assocs != [] or preloads != [] do
    error!(query, "cannot preload associations in subquery")
  end
  defp assert_no_subquery_assocs!(query) do
    query
  end

  defp subquery_select(%{select: %{expr: expr, take: take} = select} = query, adapter) do
    expr =
      case subquery_select(expr, take, query) do
        {nil, fields} ->
          {:%{}, [], fields}
        {struct, fields} ->
          {:%, [], [struct, {:%{}, [], fields}]}
      end

    query = put_in(query.select.expr, expr)
    {expr, _} = prewalk(expr, :select, query, select, 0, adapter)
    {meta, _fields, _from} = collect_fields(expr, [], :error, query, take)
    {query, meta}
  end

  defp subquery_select({:merge, _, [left, right]}, take, query) do
    {left_struct, left_fields} = subquery_select(left, take, query)
    {nil, right_fields} = subquery_select(right, take, query)
    {left_struct, Keyword.merge(left_fields, right_fields)}
  end
  defp subquery_select({:%, _, [name, map]}, take, query) do
    {_, fields} = subquery_select(map, take, query)
    {name, fields}
  end
  defp subquery_select({:%{}, _, [{:|, _, [{:&, [], [ix]}, pairs]}]} = expr, take, query) do
    assert_subquery_fields!(query, expr, pairs)
    {source, _} = source_take!(:select, query, take, ix, ix)
    {struct, fields} = subquery_struct_and_fields(source)

    # Map updates may contain virtual fields, so we need to consider those
    valid_keys = if struct, do: Map.keys(struct.__struct__), else: fields
    update_keys = Keyword.keys(pairs)

    case update_keys -- valid_keys do
      [] -> :ok
      [key | _] -> error!(query, "invalid key `#{inspect key}` on map update in subquery")
    end

    # In case of map updates, we need to remove duplicated fields
    # at query time because we use the field names as aliases and
    # duplicate aliases will lead to invalid queries.
    kept_keys = fields -- update_keys
    {struct, subquery_fields(kept_keys, ix) ++ pairs}
  end
  defp subquery_select({:%{}, _, pairs} = expr, _take, query) do
    assert_subquery_fields!(query, expr, pairs)
    {nil, pairs}
  end
  defp subquery_select({:&, _, [ix]}, take, query) do
    {source, _} = source_take!(:select, query, take, ix, ix)
    {struct, fields} = subquery_struct_and_fields(source)
    {struct, subquery_fields(fields, ix)}
  end
  defp subquery_select({{:., _, [{:&, _, [ix]}, field]}, _, []}, _take, _query) do
    {nil, subquery_fields([field], ix)}
  end
  defp subquery_select(expr, _take, query) do
    error!(query, "subquery must select a source (t), a field (t.field) or a map, got: `#{Macro.to_string(expr)}`")
  end

  defp subquery_struct_and_fields({:source, {_, schema}, _, types}) do
    {schema, Keyword.keys(types)}
  end
  defp subquery_struct_and_fields({:struct, name, types}) do
    {name, Keyword.keys(types)}
  end
  defp subquery_struct_and_fields({:map, types}) do
    {nil, Keyword.keys(types)}
  end

  defp subquery_fields(fields, ix) do
    for field <- fields do
      {field, {{:., [], [{:&, [], [ix]}, field]}, [], []}}
    end
  end

  defp subquery_types(%{select: {:map, types}}), do: types
  defp subquery_types(%{select: {:struct, _name, types}}), do: types

  defp assert_subquery_fields!(query, expr, pairs) do
    Enum.each(pairs, fn
      {key, _} when not is_atom(key) ->
        error!(query, "only atom keys are allowed when selecting a map in subquery, got: `#{Macro.to_string(expr)}`")
      {key, value} ->
        if valid_subquery_value?(value) do
          {key, value}
        else
          error!(query, "maps, lists, tuples and sources are not allowed as map values in subquery, got: `#{Macro.to_string(expr)}`")
        end
    end)
  end

  defp valid_subquery_value?({_, _}), do: false
  defp valid_subquery_value?(args) when is_list(args), do: false
  defp valid_subquery_value?({container, _, args})
       when container in [:{}, :%{}, :&] and is_list(args), do: false
  defp valid_subquery_value?(_), do: true

  defp plan_joins(query, sources, offset, adapter) do
    plan_joins(query.joins, query, [], sources, [], 1, offset, adapter)
  end

  defp plan_joins([%JoinExpr{assoc: {ix, assoc}, qual: qual, on: on, prefix: prefix} = join|t],
                     query, joins, sources, tail_sources, counter, offset, adapter) do
    schema = schema_for_association_join!(query, join, Enum.fetch!(Enum.reverse(sources), ix))
    refl = schema.__schema__(:association, assoc)

    unless refl do
      error! query, join, "could not find association `#{assoc}` on schema #{inspect schema}"
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
    child = update_in child.joins, &Enum.map(&1, fn join -> rewrite_join_prefix(join, prefix, query) end)

    last_ix = length(child.joins)
    source_ix = counter

    {_, child_from_source} = plan_source(child, child.from, adapter)

    {child_joins, child_sources, child_tail} =
      plan_joins(child, [child_from_source], offset + last_ix - 1, adapter)

    # Rewrite joins indexes as mentioned above
    child_joins = Enum.map(child_joins, &rewrite_join(&1, qual, ix, last_ix, source_ix, offset))

    # Drop the last resource which is the association owner (it is reversed)
    child_sources = Enum.drop(child_sources, -1)

    [current_source|child_sources] = child_sources
    child_sources = child_tail ++ child_sources

    plan_joins(t, query, attach_on(child_joins, on) ++ joins, [current_source|sources],
                  child_sources ++ tail_sources, counter + 1, offset + length(child_sources), adapter)
  end

  defp plan_joins([%JoinExpr{source: %Ecto.Query{} = join_query, qual: qual, on: on} = join|t],
                      query, joins, sources, tail_sources, counter, offset, adapter) do
    case join_query do
      %{order_bys: [], limit: nil, offset: nil, group_bys: [], joins: [],
        havings: [], preloads: [], assocs: [], distinct: nil, lock: nil} ->
        {from, source} = plan_source(join_query, join_query.from, adapter)
        [join] = attach_on(query_to_joins(qual, from.source, join_query, counter), on)
        plan_joins(t, query, [join|joins], [source|sources], tail_sources, counter + 1, offset, adapter)
      _ ->
        error! query, join, "queries in joins can only have `where` conditions"
    end
  end

  defp plan_joins([%JoinExpr{} = join|t],
                      query, joins, sources, tail_sources, counter, offset, adapter) do
    {join, source} = plan_source(query, %{join | ix: counter}, adapter)
    plan_joins(t, query, [join|joins], [source|sources], tail_sources, counter + 1, offset, adapter)
  end

  defp plan_joins([], _query, joins, sources, tail_sources, _counter, _offset, _adapter) do
    {joins, sources, tail_sources}
  end

  defp attach_on([%{on: on} = h | t], %{expr: expr, params: params}) do
    [%{h | on: merge_expr_and_params(:and, on, expr, params)} | t]
  end

  defp rewrite_join_prefix(%{prefix: nil, source: {_, schema}} = join, nil, query)
       when schema != nil,
       do: %{join | prefix: schema.__schema__(:prefix) || query.prefix}

  defp rewrite_join_prefix(%{prefix: nil} = join, prefix, _query)
       when prefix != nil,
       do: %{join | prefix: prefix}

  defp rewrite_join_prefix(join, _prefix, _query), do: join

  defp rewrite_join(%{on: on, ix: join_ix} = join, qual, ix, last_ix, source_ix, inc_ix) do
    expr = Macro.prewalk on.expr, fn
        {:&, meta, [join_ix]} ->
          {:&, meta, [rewrite_ix(join_ix, ix, last_ix, source_ix, inc_ix)]}
        expr = %Ecto.Query.Tagged{type: {type_ix, type}} when is_integer(type_ix) ->
          %{expr | type: {rewrite_ix(type_ix, ix, last_ix, source_ix, inc_ix), type}}
        other ->
          other
      end

    params = Enum.map(on.params, &rewrite_param_ix(&1, ix, last_ix, source_ix, inc_ix))

    %{join | on: %{on | expr: expr, params: params}, qual: qual,
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

  defp rewrite_param_ix({value, {upper, {type_ix, field}}}, ix, last_ix, source_ix, inc_ix) when is_integer(type_ix) do
    {value, {upper, {rewrite_ix(type_ix, ix, last_ix, source_ix, inc_ix), field}}}
  end

  defp rewrite_param_ix({value, {type_ix, field}}, ix, last_ix, source_ix, inc_ix) when is_integer(type_ix) do
    {value, {rewrite_ix(type_ix, ix, last_ix, source_ix, inc_ix), field}}
  end

  defp rewrite_param_ix(param, _, _, _, _), do: param

  defp schema_for_association_join!(query, join, source) do
    case source do
      {:fragment, _, _} ->
        error! query, join, "cannot perform association joins on fragment sources"

      {source, nil, _} ->
          error! query, join, "cannot perform association join on #{inspect source} " <>
                              "because it does not have a schema"

      {_, schema, _} ->
        schema

      %Ecto.SubQuery{select: {:struct, schema, _}} ->
        schema

      %Ecto.SubQuery{} ->
        error! query, join, "can only perform association joins on subqueries " <>
                            "that return a source with schema in select"

      _ ->
        error! query, join, "can only perform association joins on sources with a schema"
    end
  end

  @doc """
  Prepare the parameters by merging and casting them according to sources.
  """
  def plan_cache(query, operation, adapter, counter) do
    {query, {cache, params}} =
      traverse_exprs(query, operation, {[], []}, &{&3, merge_cache(&1, &2, &3, &4, operation, adapter)})

    {query, Enum.reverse(params), finalize_cache(query, operation, cache, counter)}
  end

  defp merge_cache(:from, _query, from, {cache, params}, _operation, _adapter) do
    {key, params} = source_cache(from, params)
    {merge_cache(key, cache, key != :nocache), params}
  end

  defp merge_cache(kind, query, expr, {cache, params}, _operation, adapter)
      when kind in ~w(select distinct limit offset)a do
    if expr do
      {params, cacheable?} = cast_and_merge_params(kind, query, expr, params, adapter)
      {merge_cache({kind, expr_to_cache(expr)}, cache, cacheable?), params}
    else
      {cache, params}
    end
  end

  defp merge_cache(kind, query, exprs, {cache, params}, _operation, adapter)
      when kind in ~w(where update group_by having order_by)a do
    {expr_cache, {params, cacheable?}} =
      Enum.map_reduce exprs, {params, true}, fn expr, {params, cacheable?} ->
        {params, current_cacheable?} = cast_and_merge_params(kind, query, expr, params, adapter)
        {expr_to_cache(expr), {params, cacheable? and current_cacheable?}}
      end

    case expr_cache do
      [] -> {cache, params}
      _  -> {merge_cache({kind, expr_cache}, cache, cacheable?), params}
    end
  end

  defp merge_cache(:join, query, exprs, {cache, params}, _operation, adapter) do
    {expr_cache, {params, cacheable?}} =
      Enum.map_reduce exprs, {params, true}, fn
        %JoinExpr{on: on, qual: qual} = join, {params, cacheable?} ->
          {key, params} = source_cache(join, params)
          {params, join_cacheable?} = cast_and_merge_params(:join, query, join, params, adapter)
          {params, on_cacheable?} = cast_and_merge_params(:join, query, on, params, adapter)
          {{qual, key, on.expr},
           {params, cacheable? and join_cacheable? and on_cacheable? and key != :nocache}}
      end

    case expr_cache do
      [] -> {cache, params}
      _  -> {merge_cache({:join, expr_cache}, cache, cacheable?), params}
    end
  end

  defp merge_cache(:windows, query, exprs, {cache, params}, _operation, adapter) do
    {expr_cache, {params, cacheable?}} =
      Enum.map_reduce exprs, {params, true}, fn {key, expr}, {params, cacheable?} ->
        {params, current_cacheable?} = cast_and_merge_params(:windows, query, expr, params, adapter)
        {{key, expr_to_cache(expr)}, {params, cacheable? and current_cacheable?}}
      end

    case expr_cache do
      [] -> {cache, params}
      _  -> {merge_cache({:windows, expr_cache}, cache, cacheable?), params}
    end
  end

  defp merge_cache(:combination, _query, combinations, cache_and_params, operation, adapter) do
    fun = &{&3, merge_cache(&1, &2, &3, &4, operation, adapter)}

    Enum.reduce combinations, cache_and_params, fn {modifier, combination_query}, {cache, params} ->
      case traverse_exprs(combination_query, operation, {[], params}, fun) do
        {_, {:nocache, _} = acc} -> acc
        {_, {inner_cache, params}} -> {[{modifier, inner_cache} | cache], params}
      end
    end
  end

  defp expr_to_cache(%BooleanExpr{op: op, expr: expr}), do: {op, expr}
  defp expr_to_cache(%QueryExpr{expr: expr}), do: expr
  defp expr_to_cache(%SelectExpr{expr: expr}), do: expr

  defp cast_and_merge_params(kind, query, expr, params, adapter) do
    Enum.reduce expr.params, {params, true}, fn {v, type}, {acc, cacheable?} ->
      case cast_param(kind, query, expr, v, type, adapter) do
        {:in, v} ->
          {Enum.reverse(v, acc), false}
        v ->
          {[v|acc], cacheable?}
      end
    end
  end

  defp merge_cache(_left, _right, false),  do: :nocache
  defp merge_cache(_left, :nocache, true), do: :nocache
  defp merge_cache(left, right, true),     do: [left|right]

  defp finalize_cache(_query, _operation, :nocache, _counter) do
    :nocache
  end

  defp finalize_cache(%{assocs: assocs, prefix: prefix, lock: lock, select: select},
                      operation, cache, counter) do
    cache =
      case select do
        %{take: take} when take != %{} ->
          [take: take] ++ cache
        _ ->
          cache
      end

    cache =
      cache
      |> prepend_if(assocs != [],  [assocs: assocs])
      |> prepend_if(prefix != nil, [prefix: prefix])
      |> prepend_if(lock != nil,   [lock: lock])

    [operation, counter | cache]
  end

  defp prepend_if(cache, true, prepend), do: prepend ++ cache
  defp prepend_if(cache, false, _prepend), do: cache

  defp source_cache(%{source: {_, nil} = source, prefix: prefix}, params),
    do: {{source, prefix}, params}
  defp source_cache(%{source: {bin, schema}, prefix: prefix}, params),
    do: {{bin, schema, schema.__schema__(:hash), prefix}, params}
  defp source_cache(%{source: {:fragment, _, _} = source, prefix: prefix}, params),
    do: {{source, prefix}, params}
  defp source_cache(%{source: %Ecto.SubQuery{params: inner, cache: key}}, params),
    do: {key, Enum.reverse(inner, params)}

  defp cast_param(_kind, query, expr, %DynamicExpr{}, _type, _value) do
    error! query, expr, "dynamic expressions can only be interpolated inside other " <>
                        "dynamic expressions or at the top level of where, having, update or a join's on"
  end
  defp cast_param(_kind, query, expr, [{key, _} | _], _type, _value) when is_atom(key) do
    error! query, expr, "keyword lists can only be interpolated at the top level of " <>
                        "where, having, distinct, order_by, update or a join's on"
  end
  defp cast_param(kind, query, expr, v, type, adapter) do
    type = field_type!(kind, query, expr, type)

    try do
      case cast_param(kind, type, v, adapter) do
        {:ok, v} -> v
        {:error, error} -> error! query, expr, error
      end
    catch
      :error, %Ecto.QueryError{} = e ->
        raise Ecto.Query.CastError, value: v, type: type, message: Exception.message(e)
    end
  end

  defp cast_param(kind, type, v, adapter) do
    with {:ok, type} <- normalize_param(kind, type, v),
         {:ok, v} <- cast_param(kind, type, v),
         do: dump_param(adapter, type, v)
  end

  @doc """
  Prepare association fields found in the query.
  """
  def plan_assocs(query) do
    plan_assocs(query, 0, query.assocs)
    query
  end

  defp plan_assocs(_query, _ix, []), do: :ok
  defp plan_assocs(query, ix, assocs) do
    # We validate the schema exists when preparing joins above
    {_, parent_schema, _} = get_source!(:preload, query, ix)

    Enum.each assocs, fn {assoc, {child_ix, child_assocs}} ->
      refl = parent_schema.__schema__(:association, assoc)

      unless refl do
        error! query, "field `#{inspect parent_schema}.#{assoc}` " <>
                      "in preload is not an association"
      end

      case find_source_expr(query, child_ix) do
        %JoinExpr{qual: qual} when qual in [:inner, :left, :inner_lateral, :left_lateral] ->
          :ok
        %JoinExpr{qual: qual} ->
          error! query, "association `#{inspect parent_schema}.#{assoc}` " <>
                        "in preload requires an inner, left or lateral join, got #{qual} join"
        _ ->
          :ok
      end

      plan_assocs(query, child_ix, child_assocs)
    end
  end

  defp plan_combinations(query, operation, adapter, counter) do
    combinations =
      Enum.map query.combinations, fn {type, combination_query} ->
        {prepared_query, _params, _key} = plan(combination_query, operation, adapter, counter)
        prepared_query = prepared_query |> ensure_select(true)
        {type, prepared_query}
      end

    Map.put(query, :combinations, combinations)
  end

  defp find_source_expr(query, 0) do
    query.from
  end

  defp find_source_expr(query, ix) do
    Enum.find(query.joins, & &1.ix == ix)
  end

  @doc """
  Used for customizing the query returning result.
  """
  def ensure_select(%{select: select} = query, _fields) when select != nil do
    query
  end
  def ensure_select(%{select: nil}, []) do
    raise ArgumentError, ":returning expects at least one field to be given, got an empty list"
  end
  def ensure_select(%{select: nil} = query, fields) when is_list(fields) do
    %{query | select: %SelectExpr{expr: {:&, [], [0]}, take: %{0 => {:any, fields}},
                                  line: __ENV__.line, file: __ENV__.file}}
  end
  def ensure_select(%{select: nil, from: %{source: {_, nil}}} = query, true) do
    error! query, "queries that do not have a schema need to explicitly pass a :select clause"
  end
  def ensure_select(%{select: nil} = query, true) do
    %{query | select: %SelectExpr{expr: {:&, [], [0]}, line: __ENV__.line, file: __ENV__.file}}
  end
  def ensure_select(%{select: nil} = query, false) do
    query
  end

  @doc """
  Normalizes and validates the query.

  After the query was planned and there is no cache
  entry, we need to update its interpolations and check
  its fields and associations exist and are valid.
  """
  def normalize(query, operation, adapter, counter) do
    query
    |> normalize_query(operation, adapter, counter)
    |> elem(0)
    |> normalize_select()
  rescue
    e ->
      # Reraise errors so we ignore the planner inner stacktrace
      filter_and_reraise e, System.stacktrace
  end

  defp normalize_query(query, operation, adapter, counter) do
    case operation do
      :all ->
        assert_no_update!(query, operation)
        assert_valid_combinations!(query)
      :update_all ->
        assert_update!(query, operation)
        assert_only_filter_expressions!(query, operation)
      :delete_all ->
        assert_no_update!(query, operation)
        assert_only_filter_expressions!(query, operation)
    end

    traverse_exprs(query, operation, counter,
                   &validate_and_increment(&1, &2, &3, &4, operation, adapter))
  end

  defp validate_and_increment(:from, query, %{source: %Ecto.SubQuery{}}, _counter, kind, _adapter) when kind != :all do
    error! query, "`#{kind}` does not allow subqueries in `from`"
  end
  defp validate_and_increment(:from, query, %{source: source} = expr, counter, _kind, adapter) do
    {source, acc} = prewalk_source(source, :from, query, expr, counter, adapter)
    {%{expr | source: source}, acc}
  end

  defp validate_and_increment(kind, query, expr, counter, _operation, adapter)
      when kind in ~w(select distinct limit offset)a do
    if expr do
      prewalk(kind, query, expr, counter, adapter)
    else
      {nil, counter}
    end
  end

  defp validate_and_increment(kind, query, exprs, counter, _operation, adapter)
       when kind in ~w(where group_by having order_by update)a do

    {exprs, counter} =
      Enum.reduce(exprs, {[], counter}, fn
        %{expr: []}, {list, acc} ->
          {list, acc}
        expr, {list, acc} ->
          {expr, acc} = prewalk(kind, query, expr, acc, adapter)
          {[expr|list], acc}
      end)
    {Enum.reverse(exprs), counter}
  end

  defp validate_and_increment(:join, query, exprs, counter, _operation, adapter) do
    Enum.map_reduce exprs, counter, fn join, acc ->
      {source, acc} = prewalk_source(join.source, :join, query, join, acc, adapter)
      {on, acc} = prewalk(:join, query, join.on, acc, adapter)
      {%{join | on: on, source: source, params: nil}, acc}
    end
  end

  defp validate_and_increment(:windows, query, exprs, counter, _operation, adapter) do
    {exprs, counter} =
      Enum.reduce(exprs, {[], counter}, fn {name, expr}, {list, acc} ->
        {expr, acc} = prewalk(:windows, query, expr, acc, adapter)
        {[{name, expr}|list], acc}
      end)

    {Enum.reverse(exprs), counter}
  end

  defp validate_and_increment(:combination, _query, combinations, counter, operation, adapter) do
    fun = &validate_and_increment(&1, &2, &3, &4, operation, adapter)

    {combinations, counter} =
      Enum.reduce combinations, {[], counter}, fn {type, combination_query}, {combinations, counter} ->
        {combination_query, counter} = traverse_exprs(combination_query, operation, counter, fun)
        {[{type, combination_query} | combinations], counter}
      end

    {Enum.reverse(combinations), counter}
  end

  defp prewalk_source({:fragment, meta, fragments}, kind, query, expr, acc, adapter) do
    {fragments, acc} = prewalk(fragments, kind, query, expr, acc, adapter)
    {{:fragment, meta, fragments}, acc}
  end
  defp prewalk_source(%Ecto.SubQuery{query: inner_query} = subquery, _kind, query, _expr, counter, adapter) do
    try do
      {inner_query, counter} = normalize_query(inner_query, :all, adapter, counter)
      {inner_query, _} = normalize_select(inner_query)
      keys = subquery |> subquery_types() |> Keyword.keys()
      inner_query = update_in(inner_query.select.fields, &Enum.zip(keys, &1))
      {%{subquery | query: inner_query}, counter}
    rescue
      e -> raise Ecto.SubQueryError, query: query, exception: e
    end
  end
  defp prewalk_source(source, _kind, _query, _expr, acc, _adapter) do
    {source, acc}
  end

  defp prewalk(:update, query, expr, counter, adapter) do
    source = get_source!(:update, query, 0)

    {inner, acc} =
      Enum.map_reduce expr.expr, counter, fn {op, kw}, counter ->
        {kw, acc} =
          Enum.map_reduce kw, counter, fn {field, value}, counter ->
            {value, acc} = prewalk(value, :update, query, expr, counter, adapter)
            {{field_source(source, field), value}, acc}
          end
        {{op, kw}, acc}
      end

    {%{expr | expr: inner, params: nil}, acc}
  end
  defp prewalk(kind, query, expr, counter, adapter) do
    {inner, acc} = prewalk(expr.expr, kind, query, expr, counter, adapter)
    {%{expr | expr: inner, params: nil}, acc}
  end

  defp prewalk({:in, in_meta, [left, {:^, meta, [param]}]}, kind, query, expr, acc, adapter) do
    {left, acc} = prewalk(left, kind, query, expr, acc, adapter)
    {right, acc} = validate_in(meta, expr, param, acc, adapter)
    {{:in, in_meta, [left, right]}, acc}
  end

  defp prewalk({{:., dot_meta, [{:&, amp_meta, [ix]}, field]}, meta, []},
               kind, query, expr, acc, _adapter) do
    extra = if kind == :select, do: [type: type!(kind, query, expr, ix, field)], else: []
    field = field_source(get_source!(kind, query, ix), field)
    {{{:., extra ++ dot_meta, [{:&, amp_meta, [ix]}, field]}, meta, []}, acc}
  end

  defp prewalk({:^, meta, [ix]}, _kind, _query, _expr, acc, _adapter) when is_integer(ix) do
    {{:^, meta, [acc]}, acc + 1}
  end

  defp prewalk({:type, _, [arg, type]}, kind, query, expr, acc, adapter) do
    {arg, acc} = prewalk(arg, kind, query, expr, acc, adapter)
    type = field_type!(kind, query, expr, type)
    {%Ecto.Query.Tagged{value: arg, tag: type, type: Ecto.Type.type(type)}, acc}
  end

  defp prewalk(%Ecto.Query.Tagged{value: v, type: type} = tagged, kind, query, expr, acc, adapter) do
    if Ecto.Type.base?(type) do
      {tagged, acc}
    else
      {dump_param(kind, query, expr, v, type, adapter), acc}
    end
  end

  defp prewalk({left, right}, kind, query, expr, acc, adapter) do
    {left, acc} = prewalk(left, kind, query, expr, acc, adapter)
    {right, acc} = prewalk(right, kind, query, expr, acc, adapter)
    {{left, right}, acc}
  end

  defp prewalk({left, meta, args}, kind, query, expr, acc, adapter) do
    {left, acc} = prewalk(left, kind, query, expr, acc, adapter)
    {args, acc} = prewalk(args, kind, query, expr, acc, adapter)
    {{left, meta, args}, acc}
  end

  defp prewalk(list, kind, query, expr, acc, adapter) when is_list(list) do
    Enum.map_reduce(list, acc, &prewalk(&1, kind, query, expr, &2, adapter))
  end

  defp prewalk(other, _kind, _query, _expr, acc, _adapter) do
    {other, acc}
  end

  defp dump_param(kind, query, expr, v, type, adapter) do
    type = field_type!(kind, query, expr, type)

    case dump_param(kind, type, v, adapter) do
      {:ok, v} ->
        v
      {:error, error} ->
        error = error <> ". Or the value is incompatible or it must be " <>
                         "interpolated (using ^) so it may be cast accordingly"
        error! query, expr, error
    end
  end

  defp dump_param(kind, type, v, adapter) do
    with {:ok, type} <- normalize_param(kind, type, v),
         do: dump_param(adapter, type, v)
  end

  defp validate_in(meta, expr, param, acc, adapter) do
    {v, t} = Enum.fetch!(expr.params, param)
    length = length(v)

    case adapter.dumpers(t, t) do
      [{:in, _} | _] -> {{:^, meta, [acc, length]}, acc + length}
      _ -> {{:^, meta, [acc, length]}, acc + 1}
    end
  end

  defp normalize_select(%{select: nil} = query) do
    {query, nil}
  end
  defp normalize_select(query) do
    %{assocs: assocs, preloads: preloads, select: select} = query
    %{take: take, expr: expr} = select
    {tag, from_take} = Map.get(take, 0, {:any, []})
    source = get_source!(:select, query, 0)
    assocs = merge_assocs(assocs, query)

    # In from, if there is a schema and we have a map tag with preloads,
    # it needs to be converted to a map in a later pass.
    {take, from_tag} =
      case source do
        {source, schema, _}
        when tag == :map and preloads != [] and is_binary(source) and schema != nil ->
          {Map.put(take, 0, {:struct, from_take}), :map}

        _ ->
          {take, :any}
      end

    {postprocess, fields, from} =
      collect_fields(expr, [], :error, query, take)

    {fields, preprocess, from} =
      case from do
        {:ok, from_pre, from_expr, from_taken} ->
          {assoc_exprs, assoc_fields} = collect_assocs([], [], query, tag, from_take, assocs)
          fields = from_taken ++ Enum.reverse(assoc_fields, Enum.reverse(fields))
          preprocess = [from_pre | Enum.reverse(assoc_exprs)]
          {fields, preprocess, {from_tag, from_expr}}

        :error when preloads != [] or assocs != [] ->
          error! query, "the binding used in `from` must be selected in `select` when using `preload`"

        :error ->
          {Enum.reverse(fields), [], :none}
      end

    select = %{
      preprocess: preprocess,
      postprocess: postprocess,
      take: from_take,
      assocs: assocs,
      from: from
    }

    combinations =
      Enum.map query.combinations, fn {type, combination_query} ->
        {combination_query, _} = normalize_select(combination_query)
        {type, combination_query}
      end

    query = %{query | combinations: combinations}
    {put_in(query.select.fields, fields), select}
  end

  # Handling of source

  defp collect_fields({:merge, _, [{:&, _, [0]}, right]}, fields, :error, query, take) do
    {expr, taken} = source_take!(:select, query, take, 0, 0)
    from = {:ok, {:source, :from}, expr, taken}

    {right, right_fields, _from} = collect_fields(right, [], from, query, take)
    from = {:ok, {:merge, {:source, :from}, right}, expr, taken ++ Enum.reverse(right_fields)}

    {{:source, :from}, fields, from}
  end

  defp collect_fields({:&, _, [0]}, fields, :error, query, take) do
    {expr, taken} = source_take!(:select, query, take, 0, 0)
    {{:source, :from}, fields, {:ok, {:source, :from}, expr, taken}}
  end

  defp collect_fields({:&, _, [0]}, fields, from, _query, _take) do
    {{:source, :from}, fields, from}
  end

  defp collect_fields({:&, _, [ix]}, fields, from, query, take) do
    {expr, taken} = source_take!(:select, query, take, ix, ix)
    {expr, Enum.reverse(taken, fields), from}
  end

  # Expression handling

  @aggs ~w(count avg min max sum row_number rank dense_rank percent_rank cume_dist ntile lag lead first_value last_value nth_value)a

  defp collect_fields({agg, _, [{{:., dot_meta, [{:&, _, [_]}, _]}, _, []} | _]} = expr,
                      fields, from, _query, _take)
       when agg in @aggs do
    type =
      case agg do
        :count -> :integer
        :row_number -> :integer
        :rank -> :integer
        :dense_rank -> :integer
        :ntile -> :integer
        :avg -> :any
        :sum -> :any
        :percent_rank -> :any
        :cume_dist -> :any
        _ -> Keyword.fetch!(dot_meta, :type)
      end

    {{:value, type}, [expr | fields], from}
  end

  defp collect_fields({:filter, _, [call, _]} = expr, fields, from, query, take) do
    {type, _, _} = collect_fields(call, fields, from, query, take)
    {type, [expr | fields], from}
  end

  defp collect_fields({:coalesce, _, [left, right]} = expr, fields, from, query, take) do
    {left_type, _, _} = collect_fields(left, fields, from, query, take)
    {right_type, _, _} = collect_fields(right, fields, from, query, take)

    type =
      case {left_type, right_type} do
        {_, {:value, type}} when type != :any -> {:value, type}
        {{:value, type}, _} when type != :any -> {:value, type}
        _ -> {:value, :any}
      end

    {type, [expr | fields], from}
  end

  defp collect_fields({:over, _, [call, window]} = expr, fields, from, query, take) do
    if is_atom(window) and not Keyword.has_key?(query.windows, window) do
      error!(query, "unknown window #{inspect window} given to over/2")
    end

    {type, _, _} = collect_fields(call, fields, from, query, take)
    {type, [expr | fields], from}
  end

  defp collect_fields({{:., dot_meta, [{:&, _, [_]}, _]}, _, []} = expr,
                      fields, from, _query, _take) do
    {{:value, Keyword.fetch!(dot_meta, :type)}, [expr | fields], from}
  end

  defp collect_fields({left, right}, fields, from, query, take) do
    {args, fields, from} = collect_args([left, right], fields, from, query, take, [])
    {{:tuple, args}, fields, from}
  end

  defp collect_fields({:{}, _, args}, fields, from, query, take) do
    {args, fields, from} = collect_args(args, fields, from, query, take, [])
    {{:tuple, args}, fields, from}
  end

  defp collect_fields({:%{}, _, [{:|, _, [data, args]}]}, fields, from, query, take) do
    {data, fields, from} = collect_fields(data, fields, from, query, take)
    {args, fields, from} = collect_kv(args, fields, from, query, take, [])
    {{:map, data, args}, fields, from}
  end

  defp collect_fields({:%{}, _, args}, fields, from, query, take) do
    {args, fields, from} = collect_kv(args, fields, from, query, take, [])
    {{:map, args}, fields, from}
  end

  defp collect_fields({:%, _, [name, {:%{}, _, [{:|, _, [data, args]}]}]}, fields, from, query, take) do
    {data, fields, from} = collect_fields(data, fields, from, query, take)
    {args, fields, from} = collect_kv(args, fields, from, query, take, [])
    struct!(name, args)
    {{:struct, name, data, args}, fields, from}
  end

  defp collect_fields({:%, _, [name, {:%{}, _, args}]}, fields, from, query, take) do
    {args, fields, from} = collect_kv(args, fields, from, query, take, [])
    struct!(name, args)
    {{:struct, name, args}, fields, from}
  end

  defp collect_fields({:merge, _, args}, fields, from, query, take) do
    {[left, right], fields, from} = collect_args(args, fields, from, query, take, [])
    {{:merge, left, right}, fields, from}
  end

  defp collect_fields({:date_add, _, [arg | _]} = expr, fields, from, query, take) do
    case collect_fields(arg, fields, from, query, take) do
      {{:value, :any}, _, _} -> {{:value, :date}, [expr | fields], from}
      {type, _, _} -> {type, [expr | fields], from}
    end
  end

  defp collect_fields({:datetime_add, _, [arg | _]} = expr, fields, from, query, take) do
    case collect_fields(arg, fields, from, query, take) do
      {{:value, :any}, _, _} -> {{:value, :naive_datetime}, [expr | fields], from}
      {type, _, _} -> {type, [expr | fields], from}
    end
  end

  defp collect_fields(args, fields, from, query, take) when is_list(args) do
    {args, fields, from} = collect_args(args, fields, from, query, take, [])
    {{:list, args}, fields, from}
  end

  defp collect_fields(expr, fields, from, _query, _take)
       when is_atom(expr) or is_binary(expr) or is_number(expr) do
    {expr, fields, from}
  end

  defp collect_fields(%Ecto.Query.Tagged{tag: tag} = expr, fields, from, _query, _take) do
    {{:value, tag}, [expr | fields], from}
  end

  defp collect_fields(expr, fields, from, _query, _take) do
    {{:value, :any}, [expr | fields], from}
  end

  defp collect_kv([{key, value} | elems], fields, from, query, take, acc) do
    {key, fields, from} = collect_fields(key, fields, from, query, take)
    {value, fields, from} = collect_fields(value, fields, from, query, take)
    collect_kv(elems, fields, from, query, take, [{key, value} | acc])
  end
  defp collect_kv([], fields, from, _query, _take, acc) do
    {Enum.reverse(acc), fields, from}
  end

  defp collect_args([elem | elems], fields, from, query, take, acc) do
    {elem, fields, from} = collect_fields(elem, fields, from, query, take)
    collect_args(elems, fields, from, query, take, [elem | acc])
  end
  defp collect_args([], fields, from, _query, _take, acc) do
    {Enum.reverse(acc), fields, from}
  end

  defp merge_assocs(assocs, query) do
    assocs
    |> Enum.reduce(%{}, fn {field, {index, children}}, acc ->
      children = merge_assocs(children, query)

      Map.update(acc, field, {index, children}, fn
        {^index, current_children} ->
          {index, merge_assocs(children ++ current_children, query)}
        {other_index, _} ->
          error! query, "association `#{field}` is being set to binding at position #{index} " <>
                        "and at position #{other_index} at the same time"
      end)
    end)
    |> Map.to_list()
  end

  defp collect_assocs(exprs, fields, query, tag, take, [{assoc, {ix, children}}|tail]) do
    case get_source!(:preload, query, ix) do
      {source, schema, _} = to_take when is_binary(source) and schema != nil ->
        {fetch, take_children} = fetch_assoc(tag, take, assoc)
        {expr, taken} = take!(to_take, query, fetch, assoc, ix)
        exprs = [expr | exprs]
        fields = Enum.reverse(taken, fields)
        {exprs, fields} = collect_assocs(exprs, fields, query, tag, take_children, children)
        {exprs, fields} = collect_assocs(exprs, fields, query, tag, take, tail)
        {exprs, fields}
      _ ->
        error! query, "can only preload sources with a schema " <>
                      "(fragments, binary and subqueries are not supported)"
    end
  end
  defp collect_assocs(exprs, fields, _query, _tag, _take, []) do
    {exprs, fields}
  end

  defp fetch_assoc(tag, take, assoc) do
    case Access.fetch(take, assoc) do
      {:ok, value} -> {{:ok, {tag, value}}, value}
      :error -> {:error, []}
    end
  end

  defp source_take!(kind, query, take, field, ix) do
    source = get_source!(kind, query, ix)
    take!(source, query, Access.fetch(take, field), field, ix)
  end

  defp take!(source, query, fetched, field, ix) do
    case {fetched, source} do
      {{:ok, {_, _}}, {:fragment, _, _}} ->
        error! query, "it is not possible to return a map/struct subset of a fragment, " <>
                      "you must explicitly return the desired individual fields"

      {{:ok, {_, []}}, {_, _, _}} ->
        error! query, "at least one field must be selected for binding `#{field}`, got an empty list"

      {{:ok, {:struct, _}}, {_, nil, _}} ->
        error! query, "struct/2 in select expects a source with a schema"

      {{:ok, {kind, fields}}, {source, schema, prefix}} ->
        dumper = if schema, do: schema.__schema__(:dump), else: %{}
        schema = if kind == :map, do: nil, else: schema
        {types, fields} = select_dump(List.wrap(fields), dumper, ix)
        {{:source, {source, schema}, prefix || query.prefix, types}, fields}

      {{:ok, {_, _}}, %Ecto.SubQuery{}} ->
        error! query, "it is not possible to return a map/struct subset of a subquery, " <>
                      "you must explicitly select the whole subquery or individual fields only"

      {:error, {:fragment, _, _}} ->
        {{:value, :map}, [{:&, [], [ix]}]}

      {:error, {_, nil, _}} ->
        {{:value, :map}, [{:&, [], [ix]}]}

      {:error, {source, schema, prefix}} ->
        {types, fields} = select_dump(schema.__schema__(:fields), schema.__schema__(:dump), ix)
        {{:source, {source, schema}, prefix || query.prefix, types}, fields}

      {:error, %Ecto.SubQuery{select: select} = subquery} ->
        fields = for {field, _} <- subquery_types(subquery), do: select_field(field, ix)
        {select, fields}
    end
  end

  defp select_dump(fields, dumper, ix) do
    fields
    |> Enum.reverse
    |> Enum.reduce({[], []}, fn
      field, {types, exprs} when is_atom(field) ->
        {source, type} = Map.get(dumper, field, {field, :any})
        {[{field, type} | types], [select_field(source, ix) | exprs]}
      _field, acc ->
        acc
    end)
  end

  defp select_field(field, ix) do
    {{:., [], [{:&, [], [ix]}, field]}, [], []}
  end

  defp get_source!(where, %{sources: sources} = query, ix) do
    elem(sources, ix)
  rescue
    ArgumentError ->
      error! query, "invalid query has specified more bindings than bindings available " <>
                    "in `#{where}` (look for `unknown_binding!` in the printed query below)"
  end

  ## Helpers

  @exprs [distinct: :distinct, select: :select, from: :from, join: :joins,
          where: :wheres, group_by: :group_bys, having: :havings, windows: :windows,
          combination: :combinations, order_by: :order_bys, limit: :limit, offset: :offset]

  # Traverse all query components with expressions.
  # Therefore from, preload, assocs and lock are not traversed.
  defp traverse_exprs(query, operation, acc, fun) do
    extra =
      case operation do
        :update_all -> [update: :updates]
        _ -> []
      end

    Enum.reduce extra ++ @exprs, {query, acc}, fn {kind, key}, {query, acc} ->
      {traversed, acc} = fun.(kind, query, Map.fetch!(query, key), acc)
      {Map.put(query, key, traversed), acc}
    end
  end

  defp field_type!(kind, query, expr, {composite, {ix, field}}) when is_integer(ix) do
    {composite, type!(kind, query, expr, ix, field)}
  end
  defp field_type!(kind, query, expr, {ix, field}) when is_integer(ix) do
    type!(kind, query, expr, ix, field)
  end
  defp field_type!(_kind, _query, _expr, type) do
    type
  end

  defp type!(_kind, _query, _expr, nil, _field), do: :any
  defp type!(kind, query, expr, ix, field) when is_integer(ix) do
    case get_source!(kind, query, ix) do
      {:fragment, _, _} ->
        :any

      {_, schema, _} ->
        type!(kind, query, expr, schema, field)

      %Ecto.SubQuery{} = subquery ->
        case Keyword.fetch(subquery_types(subquery), field) do
          {:ok, {:value, type}} ->
            type
          {:ok, _} ->
            :any
          :error ->
            error!(query, expr, "field `#{field}` does not exist in subquery")
        end
    end
  end
  defp type!(kind, query, expr, schema, field) when is_atom(schema) do
    cond do
      type = schema.__schema__(:type, field) ->
        type
      Map.has_key?(schema.__struct__, field) ->
        error! query, expr, "field `#{field}` in `#{kind}` is a virtual field in schema #{inspect schema}"
      true ->
        error! query, expr, "field `#{field}` in `#{kind}` does not exist in schema #{inspect schema}"
    end
  end

  defp normalize_param(_kind, {:out, {:array, type}}, _value) do
    {:ok, type}
  end
  defp normalize_param(_kind, {:out, :any}, _value) do
    {:ok, :any}
  end
  defp normalize_param(kind, {:out, other}, value) do
    {:error, "value `#{inspect value}` in `#{kind}` expected to be part of an array " <>
             "but matched type is #{inspect other}"}
  end
  defp normalize_param(_kind, type, _value) do
    {:ok, type}
  end

  defp cast_param(kind, type, v) do
    case Ecto.Type.cast(type, v) do
      {:ok, v} ->
        {:ok, v}
      _ ->
        {:error, "value `#{inspect v}` in `#{kind}` cannot be cast to type #{inspect type}"}
    end
  end

  defp dump_param(adapter, type, v) do
    case Ecto.Type.adapter_dump(adapter, type, v) do
      {:ok, v} ->
        {:ok, v}
      :error ->
        {:error, "value `#{inspect v}` cannot be dumped to type #{inspect type}"}
    end
  end

  defp field_source({source, schema, _}, field) when is_binary(source) and schema != nil do
    # If the field is not found we return the field itself
    # which will be checked and raise later.
    schema.__schema__(:field_source, field) || field
  end
  defp field_source(_, field) do
    field
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
      %Ecto.Query{order_bys: [], limit: nil, offset: nil, group_bys: [],
                  havings: [], preloads: [], assocs: [], distinct: nil, lock: nil,
                  windows: [], combinations: [],} ->
        query
      _ ->
        error! query, "`#{operation}` allows only `where` and `join` expressions. " <>
                      "You can exclude unwanted expressions from a query by using " <>
                      "Ecto.Query.exclude/2. Error found"
    end
  end

  defp assert_valid_combinations!(query) do
    case query.combinations do
      [] ->
        :ok

      [{kind, _} | _] ->
        has_bindings? =
          Enum.any?(query.order_bys, fn order_by ->
            Enum.any?(order_by.expr, &match?({_dir, {{:., [], [{:&, [], [_]}, _]}, [], []}}, &1))
          end)

        if has_bindings? do
          error! query, """
          cannot use bindings in `order_by` when using `#{kind}`.

          That's because the `order_by` applies to the whole `#{kind}` and not \
          an individual query. If you really want to order the results, you can wrap \
          the existing query in a subquery and then order it:

              query = #{kind}(query1, ^query2)
              from q in subquery(query), order_by: q.field

          """
        end
    end
  end

  defp filter_and_reraise(exception, stacktrace) do
    reraise exception, Enum.reject(stacktrace, &match?({__MODULE__, _, _, _}, &1))
  end

  defp error!(query, message) do
    raise Ecto.QueryError, message: message, query: query
  end

  defp error!(query, expr, message) do
    raise Ecto.QueryError, message: message, query: query, file: expr.file, line: expr.line
  end
end
