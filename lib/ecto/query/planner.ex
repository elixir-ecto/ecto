defmodule Ecto.Query.Planner do
  # Normalizes a query and its parameters.
  @moduledoc false

  alias Ecto.Query.{
    BooleanExpr,
    ByExpr,
    DynamicExpr,
    FromExpr,
    JoinExpr,
    QueryExpr,
    SelectExpr,
    LimitExpr
  }

  if map_size(%Ecto.Query{}) != 21 do
    raise "Ecto.Query match out of date in builder"
  end

  @parent_as __MODULE__
  @aggs ~w(count avg min max sum row_number rank dense_rank percent_rank cume_dist ntile lag lead first_value last_value nth_value)a

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
      0 -> last
      ix -> ix + position - 1
    end

    for {%{on: on} = join, ix} <- Enum.with_index(joins ++ [join]) do
      %{join | on: rewrite_sources(on, mapping), ix: ix + position}
    end
  end

  defp merge_expr_and_params(
         op,
         %QueryExpr{expr: left_expr, params: left_params} = struct,
         right_expr,
         right_params
       ) do
    right_expr = Ecto.Query.Builder.bump_interpolations(right_expr, left_params)
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
      Macro.prewalk(expr, fn
        %Ecto.Query.Tagged{type: type, tag: tag} = tagged ->
          %{tagged | type: rewrite_type(type, mapping), tag: rewrite_type(tag, mapping)}

        {:&, meta, [ix]} ->
          {:&, meta, [mapping.(ix)]}

        other ->
          other
      end)

    params =
      Enum.map(params, fn
        {val, type} ->
          {val, rewrite_type(type, mapping)}

        val ->
          val
      end)

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
  def new_query_cache(atom_name) do
    :ets.new(atom_name || __MODULE__, [:set, :public, read_concurrency: true])
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
    {query, params, key} = plan(query, operation, adapter)
    {cast_params, dump_params} = Enum.unzip(params)
    query_with_cache(key, query, operation, cache, adapter, counter, cast_params, dump_params)
  end

  defp query_with_cache(key, query, operation, cache, adapter, counter, cast_params, dump_params) do
    case query_lookup(key, query, operation, cache, adapter, counter) do
      {_, select, prepared} ->
        {build_meta(query, select), {:nocache, prepared}, cast_params, dump_params}

      {_key, :cached, select, cached} ->
        update = &cache_update(cache, key, &1)
        reset = &cache_reset(cache, key, &1)
        {build_meta(query, select), {:cached, update, reset, cached}, cast_params, dump_params}

      {_key, :cache, select, prepared} ->
        update = &cache_update(cache, key, &1)
        {build_meta(query, select), {:cache, update, prepared}, cast_params, dump_params}
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
  @spec plan(Ecto.Query.t(), atom(), module, map()) ::
          {planned_query :: Ecto.Query.t(), parameters :: list(), cache_key :: any()}
  def plan(query, operation, adapter, cte_names \\ %{}) do
    {query, cte_names} = plan_ctes(query, adapter, cte_names)
    query = plan_sources(query, adapter, cte_names)
    plan_subquery = &plan_subquery(&1, query, nil, adapter, false, cte_names)

    query
    |> plan_assocs()
    |> plan_combinations(adapter, cte_names)
    |> plan_expr_subqueries(:wheres, plan_subquery)
    |> plan_expr_subqueries(:havings, plan_subquery)
    |> plan_expr_subqueries(:order_bys, plan_subquery)
    |> plan_expr_subqueries(:group_bys, plan_subquery)
    |> plan_expr_subquery(:distinct, plan_subquery)
    |> plan_expr_subquery(:select, plan_subquery)
    |> plan_windows(plan_subquery)
    |> plan_cache(operation, adapter)
  rescue
    e ->
      # Reraise errors so we ignore the planner inner stacktrace
      filter_and_reraise(e, __STACKTRACE__)
  end

  @doc """
  Prepare all sources, by traversing and expanding from, joins, subqueries.
  """
  def plan_sources(query, adapter, cte_names) do
    {from, source} = plan_from(query, adapter, cte_names)

    # Set up the initial source so we can refer
    # to the parent in subqueries in joins
    query = %{query | sources: {source}}

    {joins, sources, tail_sources} =
      plan_joins(query, [source], length(query.joins), adapter, cte_names)

    %{
      query
      | from: from,
        joins: joins |> Enum.reverse(),
        sources: (tail_sources ++ sources) |> Enum.reverse() |> List.to_tuple()
    }
  end

  defp plan_from(%{from: nil} = query, _adapter, _cte_names) do
    error!(query, "query must have a from expression")
  end

  defp plan_from(
         %{from: %{source: {kind, _, _}}, preloads: preloads, assocs: assocs} = query,
         _adapter,
         _cte_names
       )
       when kind in [:fragment, :values] and (assocs != [] or preloads != []) do
    error!(query, "cannot preload associations with a #{kind} source")
  end

  defp plan_from(%{from: from} = query, adapter, cte_names) do
    plan_source(query, from, adapter, cte_names)
  end

  defp plan_source(
         query,
         %{source: %Ecto.SubQuery{} = subquery, prefix: prefix} = expr,
         adapter,
         cte_names
       ) do
    subquery = plan_subquery(subquery, query, prefix, adapter, true, cte_names)
    {%{expr | source: subquery}, subquery}
  end

  defp plan_source(query, %{source: {nil, schema}} = expr, _adapter, cte_names)
       when is_atom(schema) and schema != nil do
    source = schema.__schema__(:source)
    source_prefix = plan_source_schema_prefix(expr, schema)

    prefix =
      case cte_names do
        %{^source => _} -> source_prefix
        _ -> source_prefix || query.prefix
      end

    {%{expr | source: {source, schema}}, {source, schema, prefix}}
  end

  defp plan_source(query, %{source: {source, schema}, prefix: prefix} = expr, _adapter, cte_names)
       when is_binary(source) and is_atom(schema) do
    prefix =
      case cte_names do
        %{^source => _} -> prefix
        _ -> prefix || query.prefix
      end

    {expr, {source, schema, prefix}}
  end

  defp plan_source(
         _query,
         %{source: {kind, _, _} = source, prefix: nil} = expr,
         _adapter,
         _cte_names
       )
       when kind in [:fragment, :values],
       do: {expr, source}

  defp plan_source(query, %{source: {kind, _, _}, prefix: prefix} = expr, _adapter, _cte_names)
       when kind in [:fragment, :values],
       do: error!(query, expr, "cannot set prefix: #{inspect(prefix)} option for #{kind} sources")

  defp plan_subquery(subquery, query, prefix, adapter, source?, cte_names) do
    %{query: inner_query} = subquery

    inner_query = %{
      inner_query
      | prefix: prefix || subquery.query.prefix || query.prefix,
        aliases: Map.put(inner_query.aliases, @parent_as, query)
    }

    {inner_query, params, key} = plan(inner_query, :all, adapter, cte_names)
    assert_no_subquery_assocs!(inner_query)

    {inner_query, select} =
      inner_query
      |> ensure_select(true)
      |> normalize_subquery_select(adapter, source?)

    {_, inner_query} = pop_in(inner_query.aliases[@parent_as])
    %{subquery | query: inner_query, params: params, cache: key, select: select}
  rescue
    e -> raise Ecto.SubQueryError, query: query, exception: e
  end

  # The prefix for form are computed upfront, but not for joins
  defp plan_source_schema_prefix(%FromExpr{prefix: prefix}, _schema),
    do: prefix

  defp plan_source_schema_prefix(%JoinExpr{prefix: prefix}, schema),
    do: prefix || schema.__schema__(:prefix)

  defp assert_no_subquery_assocs!(%{assocs: assocs, preloads: preloads} = query)
       when assocs != [] or preloads != [] do
    error!(query, "cannot preload associations in subquery")
  end

  defp assert_no_subquery_assocs!(query) do
    query
  end

  defp normalize_subquery_select(query, adapter, source?) do
    {schema_or_source, expr, %{select: select} = query} =
      rewrite_subquery_select_expr(query, source?)

    {expr, _} = prewalk(expr, :select, query, select, 0, adapter)

    {{:map, types}, fields, _from} =
      collect_fields(expr, [], :none, query, select.take, true, %{})

    # types must take into account selected_as/2 aliases so that the correct fields are
    # referenced when the outer query selects the entire subquery
    types = normalize_subquery_types(types, Enum.reverse(fields), query.select.aliases, [])
    {query, subquery_source(schema_or_source, types)}
  end

  defp normalize_subquery_types(types, _fields, select_aliases, _acc)
       when select_aliases == %{} do
    types
  end

  defp normalize_subquery_types([], [], _aliases, acc) do
    Enum.reverse(acc)
  end

  defp normalize_subquery_types(
         [{alias, _} = type | types],
         [{alias, _} | fields],
         select_aliases,
         acc
       ) do
    normalize_subquery_types(types, fields, select_aliases, [type | acc])
  end

  defp normalize_subquery_types(
         [{source_alias, type_value} | types],
         [field | fields],
         select_aliases,
         acc
       ) do
    if Map.has_key?(select_aliases, source_alias) do
      raise ArgumentError, """
      the alias, #{inspect(source_alias)}, provided to `selected_as/2` conflicts
      with the subquery's automatic aliasing.

      For example, the following query is not allowed because the alias `:y`
      given to `selected_as/2` is also used by the subquery to automatically
      alias `s.y`:

        s = from(s in Schema, select: %{x: selected_as(s.x, :y), y: s.y})
        from s in subquery(s)
      """
    end

    type =
      case field do
        {select_alias, _} -> {select_alias, type_value}
        _ -> {source_alias, type_value}
      end

    normalize_subquery_types(types, fields, select_aliases, [type | acc])
  end

  defp subquery_source(nil, types), do: {:map, types}
  defp subquery_source(name, types) when is_atom(name), do: {:struct, name, types}

  defp subquery_source({:source, schema, prefix, types}, only) do
    types =
      Enum.map(only, fn {field, {:value, type}} -> {field, Keyword.get(types, field, type)} end)

    {:source, schema, prefix, types}
  end

  defp rewrite_subquery_select_expr(%{select: select} = query, source?) do
    %{expr: expr, take: take} = select

    case subquery_select(expr, take, query) do
      {schema_or_source, fields} ->
        expr = {:%{}, [], fields}
        {schema_or_source, expr, put_in(query.select.expr, expr)}

      :error when source? ->
        error!(
          query,
          "subquery/cte must select a source (t), a field (t.field) or a map, got: `#{Macro.to_string(expr)}`"
        )

      :error ->
        expr = {:%{}, [], [result: expr]}
        {nil, expr, put_in(query.select.expr, expr)}
    end
  end

  defp subquery_select({:merge, _, [left, right]}, take, query) do
    {left_struct, left_fields} = subquery_select(left, take, query)
    {right_struct, right_fields} = subquery_select(right, take, query)
    {left_struct || right_struct, Keyword.merge(left_fields, right_fields)}
  end

  defp subquery_select({:%, _, [name, map]}, take, query) do
    {_, fields} = subquery_select(map, take, query)
    {name, fields}
  end

  defp subquery_select({:%{}, _, [{:|, _, [{:&, [], [ix]}, pairs]}]} = expr, take, query) do
    assert_subquery_fields!(query, expr, pairs)
    drop = Map.new(pairs, fn {key, _} -> {key, nil} end)
    {source, _} = source_take!(:select, query, take, ix, ix, drop)

    # In case of map updates, we need to remove duplicated fields
    # at query time because we use the field names as aliases and
    # duplicate aliases will lead to invalid queries.
    kept_keys = subquery_source_fields(source) -- Keyword.keys(pairs)
    {keep_source_or_struct(source), subquery_fields(kept_keys, ix) ++ pairs}
  end

  defp subquery_select({:%{}, _, pairs} = expr, _take, query) do
    assert_subquery_fields!(query, expr, pairs)
    {nil, pairs}
  end

  defp subquery_select({:&, _, [ix]}, take, query) do
    {source, _} = source_take!(:select, query, take, ix, ix, %{})
    fields = subquery_source_fields(source)
    {keep_source_or_struct(source), subquery_fields(fields, ix)}
  end

  defp subquery_select({{:., _, [{:&, _, [_]}, field]}, _, []} = expr, _take, _query) do
    {nil, [{field, expr}]}
  end

  defp subquery_select(_expr, _take, _query) do
    :error
  end

  defp subquery_fields(fields, ix) do
    for field <- fields do
      {field, {{:., [], [{:&, [], [ix]}, field]}, [], []}}
    end
  end

  defp keep_source_or_struct({:source, _, _, _} = source), do: source
  defp keep_source_or_struct({:struct, name, _}), do: name
  defp keep_source_or_struct(_), do: nil

  defp subquery_source_fields({:source, _, _, types}), do: Keyword.keys(types)
  defp subquery_source_fields({:struct, _, types}), do: Keyword.keys(types)
  defp subquery_source_fields({:map, types}), do: Keyword.keys(types)

  defp subquery_type_for({:source, _, _, fields}, field), do: Keyword.fetch(fields, field)

  defp subquery_type_for({:struct, _name, types}, field),
    do: subquery_type_for_value(types, field)

  defp subquery_type_for({:map, types}, field), do: subquery_type_for_value(types, field)

  defp subquery_type_for_value(types, field) do
    case Keyword.fetch(types, field) do
      {:ok, {:value, type}} -> {:ok, type}
      {:ok, _} -> {:ok, :any}
      :error -> :error
    end
  end

  defp assert_subquery_fields!(query, expr, pairs) do
    Enum.each(pairs, fn
      {key, _} when not is_atom(key) ->
        error!(
          query,
          "only atom keys are allowed when selecting a map in subquery, got: `#{Macro.to_string(expr)}`"
        )

      {key, value} ->
        if valid_subquery_value?(value) do
          {key, value}
        else
          error!(
            query,
            "atoms, structs, maps, lists, tuples and sources are not allowed as map values in subquery, got: `#{Macro.to_string(expr)}`"
          )
        end
    end)
  end

  defp valid_subquery_value?({_, _}), do: false
  defp valid_subquery_value?(args) when is_list(args), do: false

  defp valid_subquery_value?({container, _, args})
       when container in [:{}, :%{}, :&, :%] and is_list(args),
       do: false

  defp valid_subquery_value?(nil), do: true
  defp valid_subquery_value?(arg) when is_atom(arg), do: is_boolean(arg)
  defp valid_subquery_value?(_), do: true

  defp plan_joins(query, sources, offset, adapter, cte_names) do
    plan_joins(query.joins, query, [], sources, [], 1, offset, adapter, cte_names)
  end

  defp plan_joins(
         [%JoinExpr{assoc: {ix, assoc}, qual: qual, on: on, prefix: prefix} = join | t],
         query,
         joins,
         sources,
         tail_sources,
         counter,
         offset,
         adapter,
         cte_names
       ) do
    source = fetch_source!(sources, ix)
    schema = schema_for_association_join!(query, join, source)
    refl = schema.__schema__(:association, assoc)

    unless refl do
      error!(query, join, "could not find association `#{assoc}` on schema #{inspect(schema)}")
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

    # Rewrite prefixes:
    # 1. the child query has the parent query prefix
    #    (note the child query should NEVER have a prefix)
    # 2. from and joins can have their prefixes explicitly
    #    overwritten by the join prefix
    child = rewrite_prefix(child, query.prefix)
    child = update_in(child.from, &rewrite_prefix(&1, prefix))
    child = update_in(child.joins, &Enum.map(&1, fn join -> rewrite_prefix(join, prefix) end))

    last_ix = length(child.joins)
    source_ix = counter

    {_, child_from_source} = plan_source(child, child.from, adapter, cte_names)

    {child_joins, child_sources, child_tail} =
      plan_joins(child, [child_from_source], offset + last_ix - 1, adapter, cte_names)

    # Rewrite joins indexes as mentioned above
    child_joins = Enum.map(child_joins, &rewrite_join(&1, qual, ix, last_ix, source_ix, offset))

    # Drop the last resource which is the association owner (it is reversed)
    child_sources = Enum.drop(child_sources, -1)

    [current_source | child_sources] = child_sources
    child_sources = child_tail ++ child_sources

    plan_joins(
      t,
      query,
      attach_on(child_joins, on) ++ joins,
      [current_source | sources],
      child_sources ++ tail_sources,
      counter + 1,
      offset + length(child_sources),
      adapter,
      cte_names
    )
  end

  defp plan_joins(
         [
           %JoinExpr{source: %Ecto.Query{} = join_query, qual: qual, on: on, prefix: prefix} =
             join
           | t
         ],
         query,
         joins,
         sources,
         tail_sources,
         counter,
         offset,
         adapter,
         cte_names
       ) do
    case join_query do
      %{
        order_bys: [],
        limit: nil,
        offset: nil,
        group_bys: [],
        joins: [],
        havings: [],
        preloads: [],
        assocs: [],
        distinct: nil,
        lock: nil
      } ->
        join_query = rewrite_prefix(join_query, query.prefix)
        from = rewrite_prefix(join_query.from, prefix)
        {from, source} = plan_source(join_query, from, adapter, cte_names)
        [join] = attach_on(query_to_joins(qual, from.source, join_query, counter), on)

        plan_joins(
          t,
          query,
          [join | joins],
          [source | sources],
          tail_sources,
          counter + 1,
          offset,
          adapter,
          cte_names
        )

      _ ->
        error!(query, join, """
        invalid query was interpolated in a join.
        If you want to pass a query to a join, you must either:

          1. Make sure the query only has `where` conditions (which will be converted to ON clauses)
          2. Or wrap the query in a subquery by calling subquery(query)
        """)
    end
  end

  defp plan_joins(
         [%JoinExpr{} = join | t],
         query,
         joins,
         sources,
         tail_sources,
         counter,
         offset,
         adapter,
         cte_names
       ) do
    {join, source} = plan_source(query, %{join | ix: counter}, adapter, cte_names)

    plan_joins(
      t,
      query,
      [join | joins],
      [source | sources],
      tail_sources,
      counter + 1,
      offset,
      adapter,
      cte_names
    )
  end

  defp plan_joins(
         [],
         _query,
         joins,
         sources,
         tail_sources,
         _counter,
         _offset,
         _adapter,
         _cte_names
       ) do
    {joins, sources, tail_sources}
  end

  defp attach_on([%{on: on} = h | t], %{expr: expr, params: params}) do
    [%{h | on: merge_expr_and_params(:and, on, expr, params)} | t]
  end

  defp rewrite_prefix(expr, nil), do: expr
  defp rewrite_prefix(%{prefix: nil} = expr, prefix), do: %{expr | prefix: prefix}
  defp rewrite_prefix(expr, _prefix), do: expr

  defp rewrite_join(%{on: on, ix: join_ix} = join, qual, ix, last_ix, source_ix, inc_ix) do
    expr =
      Macro.prewalk(on.expr, fn
        {:&, meta, [join_ix]} ->
          {:&, meta, [rewrite_ix(join_ix, ix, last_ix, source_ix, inc_ix)]}

        expr = %Ecto.Query.Tagged{type: {type_ix, type}} when is_integer(type_ix) ->
          %{expr | type: {rewrite_ix(type_ix, ix, last_ix, source_ix, inc_ix), type}}

        other ->
          other
      end)

    params = Enum.map(on.params, &rewrite_param_ix(&1, ix, last_ix, source_ix, inc_ix))

    %{
      join
      | on: %{on | expr: expr, params: params},
        qual: qual,
        ix: rewrite_ix(join_ix, ix, last_ix, source_ix, inc_ix)
    }
  end

  # We need to replace the source by the one from the assoc
  defp rewrite_ix(0, ix, _last_ix, _source_ix, _inc_x), do: ix

  # The last entry will have the current source index
  defp rewrite_ix(last_ix, _ix, last_ix, source_ix, _inc_x), do: source_ix

  # All above last are already correct
  defp rewrite_ix(join_ix, _ix, last_ix, _source_ix, _inc_ix) when join_ix > last_ix, do: join_ix

  # All others need to be incremented by the offset sources
  defp rewrite_ix(join_ix, _ix, _last_ix, _source_ix, inc_ix), do: join_ix + inc_ix

  defp rewrite_param_ix({value, {upper, {type_ix, field}}}, ix, last_ix, source_ix, inc_ix)
       when is_integer(type_ix) do
    {value, {upper, {rewrite_ix(type_ix, ix, last_ix, source_ix, inc_ix), field}}}
  end

  defp rewrite_param_ix({value, {type_ix, field}}, ix, last_ix, source_ix, inc_ix)
       when is_integer(type_ix) do
    {value, {rewrite_ix(type_ix, ix, last_ix, source_ix, inc_ix), field}}
  end

  defp rewrite_param_ix(param, _, _, _, _), do: param

  defp fetch_source!(sources, ix) when is_integer(ix) do
    case Enum.reverse(sources) |> Enum.fetch(ix) do
      {:ok, source} ->
        source

      :error ->
        raise ArgumentError, "could not find a source with index `#{ix}` in `#{inspect(sources)}"
    end
  end

  defp fetch_source!(_, ix) do
    raise ArgumentError,
          "invalid binding index: `#{inspect(ix)}` (check if you're binding using a valid :as atom)"
  end

  defp schema_for_association_join!(query, join, source) do
    case source do
      {:fragment, _, _} ->
        error!(query, join, "cannot perform association joins on fragment sources")

      {source, nil, _} ->
        error!(
          query,
          join,
          "cannot perform association join on #{inspect(source)} " <>
            "because it does not have a schema"
        )

      {_, schema, _} ->
        schema

      %Ecto.SubQuery{select: {:source, {_, schema}, _, _}} ->
        schema

      %Ecto.SubQuery{select: {:struct, schema, _}} ->
        schema

      %Ecto.SubQuery{} ->
        error!(
          query,
          join,
          "can only perform association joins on subqueries " <>
            "that return a source with schema in select"
        )

      _ ->
        error!(query, join, "can only perform association joins on sources with a schema")
    end
  end

  # An optimized version of plan subqueries that only modifies the query when necessary.
  defp plan_expr_subqueries(query, key, fun) do
    query
    |> Map.fetch!(key)
    |> plan_expr_subqueries([], query, key, fun)
  end

  defp plan_expr_subqueries([%{subqueries: []} = head | tail], acc, query, key, fun) do
    plan_expr_subqueries(tail, [head | acc], query, key, fun)
  end

  defp plan_expr_subqueries([head | tail], acc, query, key, fun) do
    exprs =
      Enum.reduce([head | tail], acc, fn
        %{subqueries: []} = expr, acc ->
          [expr | acc]

        %{subqueries: subqueries} = expr, acc ->
          [%{expr | subqueries: Enum.map(subqueries, fun)} | acc]
      end)

    %{query | key => Enum.reverse(exprs)}
  end

  defp plan_expr_subqueries([], _acc, query, _key, _fun) do
    query
  end

  defp plan_expr_subquery(query, key, fun) do
    with %{^key => %{subqueries: [_ | _] = subqueries} = expr} <- query do
      %{query | key => %{expr | subqueries: Enum.map(subqueries, fun)}}
    end
  end

  defp plan_windows(%{windows: []} = query, _fun), do: query

  defp plan_windows(query, fun) do
    windows =
      Enum.map(query.windows, fn
        {key, %{subqueries: []} = window} ->
          {key, window}

        {key, %{subqueries: subqueries} = window} ->
          {key, %{window | subqueries: Enum.map(subqueries, fun)}}
      end)

    %{query | windows: windows}
  end

  @doc """
  Prepare the parameters by merging and casting them according to sources.
  """
  def plan_cache(query, operation, adapter) do
    {query, params, cache} = traverse_cache(query, operation, {[], []}, adapter)
    {query, Enum.reverse(params), cache}
  end

  defp traverse_cache(query, operation, cache_params, adapter) do
    fun = &{&3, merge_cache(&1, &2, &3, &4, operation, adapter)}
    {query, {cache, params}} = traverse_exprs(query, operation, cache_params, fun)
    {query, params, finalize_cache(query, operation, cache)}
  end

  defp merge_cache(:from, query, from, {cache, params}, _operation, adapter) do
    {key, params} = source_cache(from, params)
    {params, source_cacheable?} = cast_and_merge_params(:from, query, from, params, adapter)
    {merge_cache({:from, key, from.hints}, cache, source_cacheable? and key != :nocache), params}
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
      Enum.map_reduce(exprs, {params, true}, fn expr, {params, cacheable?} ->
        {params, current_cacheable?} = cast_and_merge_params(kind, query, expr, params, adapter)
        {expr_to_cache(expr), {params, cacheable? and current_cacheable?}}
      end)

    case expr_cache do
      [] -> {cache, params}
      _ -> {merge_cache({kind, expr_cache}, cache, cacheable?), params}
    end
  end

  defp merge_cache(:join, query, exprs, {cache, params}, _operation, adapter) do
    {expr_cache, {params, cacheable?}} =
      Enum.map_reduce(exprs, {params, true}, fn
        %JoinExpr{on: on, qual: qual, hints: hints} = join, {params, cacheable?} ->
          {key, params} = source_cache(join, params)
          {params, join_cacheable?} = cast_and_merge_params(:join, query, join, params, adapter)
          {params, on_cacheable?} = cast_and_merge_params(:join, query, on, params, adapter)

          {{qual, key, on.expr, hints},
           {params, cacheable? and join_cacheable? and on_cacheable? and key != :nocache}}
      end)

    case expr_cache do
      [] -> {cache, params}
      _ -> {merge_cache({:join, expr_cache}, cache, cacheable?), params}
    end
  end

  defp merge_cache(:windows, query, exprs, {cache, params}, _operation, adapter) do
    {expr_cache, {params, cacheable?}} =
      Enum.map_reduce(exprs, {params, true}, fn {key, expr}, {params, cacheable?} ->
        {params, current_cacheable?} =
          cast_and_merge_params(:windows, query, expr, params, adapter)

        {{key, expr_to_cache(expr)}, {params, cacheable? and current_cacheable?}}
      end)

    case expr_cache do
      [] -> {cache, params}
      _ -> {merge_cache({:windows, expr_cache}, cache, cacheable?), params}
    end
  end

  defp merge_cache(:combination, _query, combinations, cache_and_params, operation, adapter) do
    # In here we add each combination as its own entry in the cache key.
    # We could group them to avoid multiple keys, but since they are uncommon, we keep it simple.
    Enum.reduce(combinations, cache_and_params, fn {modifier, query}, {cache, params} ->
      {_, params, inner_cache} = traverse_cache(query, operation, {[], params}, adapter)
      {merge_cache({modifier, inner_cache}, cache, inner_cache != :nocache), params}
    end)
  end

  defp merge_cache(:with_cte, _query, nil, cache_and_params, _operation, _adapter) do
    cache_and_params
  end

  defp merge_cache(:with_cte, query, with_expr, cache_and_params, _operation, adapter) do
    %{queries: queries, recursive: recursive} = with_expr
    key = if recursive, do: :recursive_cte, else: :non_recursive_cte

    # In here we add each cte as its own entry in the cache key.
    # We could group them to avoid multiple keys, but since they are uncommon, we keep it simple.
    Enum.reduce(queries, cache_and_params, fn
      {name, opts, %Ecto.Query{} = query}, {cache, params} ->
        {_, params, inner_cache} = traverse_cache(query, :all, {[], params}, adapter)

        {merge_cache(
           {key, name, opts[:materialized], opts[:operation], inner_cache},
           cache,
           inner_cache != :nocache
         ), params}

      {name, opts, %Ecto.Query.QueryExpr{} = query_expr}, {cache, params} ->
        {params, cacheable?} =
          cast_and_merge_params(:with_cte, query, query_expr, params, adapter)

        {merge_cache(
           {key, name, opts[:materialized], opts[:operation], expr_to_cache(query_expr)},
           cache,
           cacheable?
         ), params}
    end)
  end

  defp expr_to_cache(%QueryExpr{expr: expr}), do: expr

  defp expr_to_cache(%SelectExpr{expr: expr, subqueries: []}), do: expr

  defp expr_to_cache(%SelectExpr{expr: expr, subqueries: subqueries}) do
    {expr, Enum.map(subqueries, fn %{cache: cache} -> {:subquery, cache} end)}
  end

  defp expr_to_cache(%ByExpr{expr: expr, subqueries: []}), do: expr

  defp expr_to_cache(%ByExpr{expr: expr, subqueries: subqueries}) do
    {expr, Enum.map(subqueries, fn %{cache: cache} -> {:subquery, cache} end)}
  end

  defp expr_to_cache(%BooleanExpr{op: op, expr: expr, subqueries: []}), do: {op, expr}

  defp expr_to_cache(%BooleanExpr{op: op, expr: expr, subqueries: subqueries}) do
    # Alternate implementation could be replace {:subquery, i} expression in expr.
    # Current strategy appends [{:subquery, i, cache}], where cache is the cache key for this subquery.
    {op, expr, Enum.map(subqueries, fn %{cache: cache} -> {:subquery, cache} end)}
  end

  defp expr_to_cache(%LimitExpr{expr: expr, with_ties: with_ties}), do: {with_ties, expr}

  @spec cast_and_merge_params(atom, Ecto.Query.t(), any, list, module) ::
          {params :: list, cacheable? :: boolean}
  defp cast_and_merge_params(kind, query, expr, params, adapter) do
    Enum.reduce(expr.params, {params, true}, fn
      {:subquery, i}, {acc, cacheable?} ->
        # This is the place holder to intersperse subquery parameters.
        %Ecto.SubQuery{params: subparams, cache: cache} = Enum.fetch!(expr.subqueries, i)
        {Enum.reverse(subparams, acc), cacheable? and cache != :nocache}

      {v, type}, {acc, cacheable?} ->
        case cast_param(kind, query, expr, v, type, adapter) do
          {cast_v, {:in, dump_v}} -> {split_variadic_params(cast_v, dump_v, acc), false}
          {cast_v, {:splice, dump_v}} -> {split_variadic_params(cast_v, dump_v, acc), cacheable?}
          cast_v_and_dump_v -> {[cast_v_and_dump_v | acc], cacheable?}
        end
    end)
  end

  defp split_variadic_params(cast_v, dump_v, acc) do
    Enum.zip(cast_v, dump_v) |> Enum.reverse(acc)
  end

  defp merge_cache(_left, _right, false), do: :nocache
  defp merge_cache(_left, :nocache, true), do: :nocache
  defp merge_cache(left, right, true), do: [left | right]

  defp finalize_cache(_query, _operation, :nocache) do
    :nocache
  end

  defp finalize_cache(query, operation, cache) do
    %{assocs: assocs, prefix: prefix, lock: lock, select: select, aliases: aliases} = query
    aliases = Map.delete(aliases, @parent_as)

    cache =
      case select do
        %{take: take} when take != %{} ->
          [take: take] ++ cache

        _ ->
          cache
      end

    cache =
      cache
      |> prepend_if(assocs != [], assocs: assocs)
      |> prepend_if(prefix != nil, prefix: prefix)
      |> prepend_if(lock != nil, lock: lock)
      |> prepend_if(aliases != %{}, aliases: aliases)

    [operation | cache]
  end

  defp prepend_if(cache, true, prepend), do: prepend ++ cache
  defp prepend_if(cache, false, _prepend), do: cache

  defp source_cache(%{source: {_, nil} = source, prefix: prefix}, params),
    do: {{source, prefix}, params}

  defp source_cache(%{source: {bin, schema}, prefix: prefix}, params),
    do: {{bin, schema, schema.__schema__(:hash), prefix}, params}

  defp source_cache(%{source: {:fragment, _, _} = source, prefix: prefix}, params),
    do: {{source, prefix}, params}

  defp source_cache(%{source: {:values, _, _}}, params),
    do: {:nocache, params}

  defp source_cache(%{source: %Ecto.SubQuery{params: inner, cache: key}}, params),
    do: {key, Enum.reverse(inner, params)}

  defp cast_param(_kind, query, expr, %DynamicExpr{}, _type, _value) do
    error!(
      query,
      expr,
      "invalid dynamic expression",
      "dynamic expressions can only be interpolated at the top level of where, having, group_by, order_by, select, update or a join's on"
    )
  end

  defp cast_param(_kind, query, expr, [{key, _} | _], _type, _value) when is_atom(key) do
    error!(
      query,
      expr,
      "invalid keyword list",
      "keyword lists are only allowed at the top level of where, having, distinct, order_by, update or a join's on"
    )
  end

  defp cast_param(_kind, query, expr, %x{}, {:in, _type}, _value)
       when x in [Ecto.Query, Ecto.SubQuery] do
    error!(
      query,
      expr,
      "an #{inspect(x)} struct is not supported as right-side value of `in` operator",
      "Did you mean to write `expr in subquery(query)` instead?"
    )
  end

  defp cast_param(kind, query, expr, v, type, adapter) do
    type = field_type!(kind, query, expr, type)

    with {:ok, type} <- normalize_param(kind, type, v),
         {:ok, cast_v} <- cast_param(kind, type, v),
         {:ok, dump_v} <- dump_param(adapter, type, cast_v) do
      {cast_v, dump_v}
    else
      {:error, message} ->
        e =
          Ecto.QueryError.exception(
            message: message,
            query: query,
            file: expr.file,
            line: expr.line
          )

        raise Ecto.Query.CastError, value: v, type: type, message: Exception.message(e)
    end
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
    # We validate the schema exists when preparing joins.
    parent_schema =
      case get_preload_source!(query, ix) do
        {_, schema, _} ->
          schema

        %Ecto.SubQuery{select: {:source, {_, schema}, _, _}} ->
          schema
      end

    Enum.each(assocs, fn {assoc, {child_ix, child_assocs}} ->
      refl = parent_schema.__schema__(:association, assoc)

      unless refl do
        error!(
          query,
          "field `#{inspect(parent_schema)}.#{assoc}` " <>
            "in preload is not an association"
        )
      end

      case find_source_expr(query, child_ix) do
        %JoinExpr{qual: qual} when qual in [:inner, :left, :inner_lateral, :left_lateral] ->
          :ok

        %JoinExpr{qual: qual} ->
          error!(
            query,
            "association `#{inspect(parent_schema)}.#{assoc}` " <>
              "in preload requires an inner, left or lateral join, got #{qual} join"
          )

        _ ->
          :ok
      end

      plan_assocs(query, child_ix, child_assocs)
    end)
  end

  defp plan_combinations(query, adapter, cte_names) do
    combinations =
      Enum.map(query.combinations, fn {type, combination_query} ->
        {prepared_query, _params, _key} =
          combination_query |> attach_prefix(query) |> plan(:all, adapter, cte_names)

        prepared_query = prepared_query |> ensure_select(true)
        {type, prepared_query}
      end)

    %{query | combinations: combinations}
  end

  defp plan_ctes(%Ecto.Query{with_ctes: nil} = query, _adapter, cte_names), do: {query, cte_names}

  defp plan_ctes(%Ecto.Query{with_ctes: %{queries: queries}} = query, adapter, cte_names) do
    {queries, cte_names} =
      Enum.map_reduce(queries, cte_names, fn
        {name, opts, %Ecto.Query{} = cte_query}, cte_names ->
          cte_names = Map.put(cte_names, name, [])

          {planned_query, _params, _key} =
            cte_query |> attach_prefix(query) |> plan(:all, adapter, cte_names)

          planned_query = planned_query |> ensure_select(true)
          {{name, opts, planned_query}, cte_names}

        {name, opts, other}, cte_names ->
          {{name, opts, other}, cte_names}
      end)

    {put_in(query.with_ctes.queries, queries), cte_names}
  end

  defp find_source_expr(query, 0) do
    query.from
  end

  defp find_source_expr(query, ix) do
    Enum.find(query.joins, &(&1.ix == ix))
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
    %{
      query
      | select: %SelectExpr{
          expr: {:&, [], [0]},
          take: %{0 => {:any, fields}},
          line: __ENV__.line,
          file: __ENV__.file
        }
    }
  end

  def ensure_select(%{select: nil, from: %{source: {_, nil}}} = query, true) do
    error!(query, "queries that do not have a schema need to explicitly pass a :select clause")
  end

  def ensure_select(%{select: nil, from: %{source: {:fragment, _, _}}} = query, true) do
    error!(query, "queries from a fragment need to explicitly pass a :select clause")
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
    |> normalize_select(keep_literals?(operation, query))
  rescue
    e ->
      # Reraise errors so we ignore the planner inner stacktrace
      filter_and_reraise(e, __STACKTRACE__)
  end

  defp keep_literals?(:insert_all, _), do: true
  defp keep_literals?(_, %{combinations: combinations}), do: combinations != []

  defp normalize_query(query, operation, adapter, counter) do
    case operation do
      :all ->
        assert_no_update!(query, operation)

      :insert_all ->
        assert_no_update!(query, operation)

      :update_all ->
        assert_update!(query, operation)
        assert_only_filter_expressions!(query, operation)

      :delete_all ->
        assert_no_update!(query, operation)
        assert_only_filter_expressions!(query, operation)
    end

    traverse_exprs(
      query,
      operation,
      counter,
      &validate_and_increment(&1, &2, &3, &4, operation, adapter)
    )
  end

  defp validate_and_increment(:from, query, %{source: %Ecto.SubQuery{}}, _counter, kind, _adapter)
       when kind not in ~w(all insert_all)a do
    error!(query, "`#{kind}` does not allow subqueries in `from`")
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
          {[expr | list], acc}
      end)

    {Enum.reverse(exprs), counter}
  end

  defp validate_and_increment(:with_cte, _query, nil, counter, _operation, _adapter) do
    {nil, counter}
  end

  defp validate_and_increment(:with_cte, query, with_expr, counter, _operation, adapter) do
    fun = &validate_and_increment(&1, &2, &3, &4, :all, adapter)

    {queries, counter} =
      Enum.reduce(with_expr.queries, {[], counter}, fn
        {name, opts, %Ecto.Query{} = inner_query}, {queries, counter} ->
          inner_query = put_in(inner_query.aliases[@parent_as], query)

          # We don't want to use normalize_subquery_select because we are
          # going to prepare the whole query ourselves next.
          {_, _, inner_query} = rewrite_subquery_select_expr(inner_query, true)
          {inner_query, counter} = traverse_exprs(inner_query, opts.operation, counter, fun)

          # Now compute the fields as keyword lists so we emit AS in Ecto query.
          %{select: %{expr: expr, take: take, aliases: aliases}} = inner_query

          {{:map, types}, fields, _from} =
            collect_fields(expr, [], :none, inner_query, take, true, %{})

          fields = cte_fields(Keyword.keys(types), Enum.reverse(fields), aliases)
          inner_query = put_in(inner_query.select.fields, fields)
          {_, inner_query} = pop_in(inner_query.aliases[@parent_as])

          {[{name, opts, inner_query} | queries], counter}

        {name, opts, %QueryExpr{expr: {:fragment, _, _} = fragment} = query_expr},
        {queries, counter} ->
          {fragment, counter} =
            prewalk_source(fragment, :with_cte, query, with_expr, counter, adapter)

          query_expr = %{query_expr | expr: fragment}
          {[{name, opts, query_expr} | queries], counter}
      end)

    {%{with_expr | queries: Enum.reverse(queries)}, counter}
  end

  defp validate_and_increment(:join, query, exprs, counter, _operation, adapter) do
    Enum.map_reduce(exprs, counter, fn join, acc ->
      {source, acc} = prewalk_source(join.source, :join, query, join, acc, adapter)
      {on, acc} = prewalk(:join, query, join.on, acc, adapter)
      {%{join | on: on, source: source, params: nil}, acc}
    end)
  end

  defp validate_and_increment(:windows, query, exprs, counter, _operation, adapter) do
    {exprs, counter} =
      Enum.reduce(exprs, {[], counter}, fn {name, expr}, {list, acc} ->
        {expr, acc} = prewalk(:windows, query, expr, acc, adapter)
        {[{name, expr} | list], acc}
      end)

    {Enum.reverse(exprs), counter}
  end

  defp validate_and_increment(:combination, query, combinations, counter, operation, adapter) do
    fun = &validate_and_increment(&1, &2, &3, &4, operation, adapter)
    parent_aliases = query.aliases[@parent_as]

    {combinations, counter} =
      Enum.reduce(combinations, {[], counter}, fn {type, combination_query},
                                                  {combinations, counter} ->
        combination_query = put_in(combination_query.aliases[@parent_as], parent_aliases)
        {combination_query, counter} = traverse_exprs(combination_query, operation, counter, fun)
        {combination_query, _} = combination_query |> normalize_select(true)
        {_, combination_query} = pop_in(combination_query.aliases[@parent_as])
        {[{type, combination_query} | combinations], counter}
      end)

    {Enum.reverse(combinations), counter}
  end

  defp validate_json_path!([path_field | rest], field, {:parameterized, {Ecto.Embedded, embed}})
       when is_binary(path_field) or is_integer(path_field) do
    case embed do
      %{related: related, cardinality: :one} ->
        unless Enum.any?(related.__schema__(:fields), &(Atom.to_string(&1) == path_field)) do
          raise "field `#{path_field}` does not exist in #{inspect(related)}"
        end

        type = related.__schema__(:type, String.to_atom(path_field))
        validate_json_path!(rest, path_field, type)

      %{related: _, cardinality: :many} ->
        unless is_integer(path_field) do
          raise "cannot use `#{path_field}` to refer to an item in `embeds_many`"
        end

        updated_embed = %{embed | cardinality: :one}
        validate_json_path!(rest, path_field, {:parameterized, {Ecto.Embedded, updated_embed}})

      other ->
        raise "expected field `#{field}` to be of type embed, got: `#{inspect(other)}`"
    end
  end

  defp validate_json_path!([path_field | rest], field, {:parameterized, {Ecto.Embedded, embed}}) do
    case embed do
      %{related: _, cardinality: :one} ->
        # A source field cannot be used to validate whether the next step in the
        # path exists in the embedded schema, so we stop here. If there is an error
        # later in the path it will be caught by the driver.
        :ok

      %{related: _, cardinality: :many} ->
        # The source field may not be an integer but for the sake of validating
        # the rest of the path, we assume it is. The error will be caught later
        # by the driver if it is not.
        updated_embed = %{embed | cardinality: :one}
        validate_json_path!(rest, path_field, {:parameterized, {Ecto.Embedded, updated_embed}})

      other ->
        raise "expected field `#{field}` to be of type embed, got: `#{inspect(other)}`"
    end
  end

  defp validate_json_path!([_path_field | _rest] = path, field, other_type) do
    case Ecto.Type.type(other_type) do
      :any ->
        :ok

      :map ->
        :ok

      {:map, _} ->
        :ok

      {:parameterized, {type, _}} ->
        validate_json_path!(path, field, type)

      type ->
        raise "expected field `#{field}` to be an embed or a map, got: `#{inspect(type)}`"
    end
  end

  defp validate_json_path!([], _field, _type) do
    :ok
  end

  defp prewalk_source({:fragment, meta, fragments}, kind, query, expr, acc, adapter) do
    {fragments, acc} = prewalk(fragments, kind, query, expr, acc, adapter)
    {{:fragment, meta, fragments}, acc}
  end

  defp prewalk_source({:values, meta, [types, num_rows]}, _kind, _query, _expr, acc, _adapter) do
    length = num_rows * length(types)
    # Adapters will use the schema types to cast the values
    schema_types = Enum.map(types, fn {field, type} -> {field, Ecto.Type.type(type)} end)
    {{:values, meta, [schema_types, acc, num_rows]}, acc + length}
  end

  defp prewalk_source(
         %Ecto.SubQuery{query: inner_query} = subquery,
         kind,
         query,
         _expr,
         counter,
         adapter
       ) do
    try do
      inner_query = put_in(inner_query.aliases[@parent_as], query)
      {inner_query, counter} = normalize_query(inner_query, :all, adapter, counter)
      {inner_query, _} = normalize_select(inner_query, true)
      {_, inner_query} = pop_in(inner_query.aliases[@parent_as])

      # If the subquery comes from a select, we are not really interested on the fields
      inner_query =
        if kind == :where do
          inner_query
        else
          update_in(inner_query.select.fields, fn fields ->
            # fields are aliased by the subquery source, unless
            # already aliased by selected_as/2
            subquery.select
            |> subquery_source_fields()
            |> Enum.zip(fields)
            |> Enum.map(fn
              {_source_alias, {select_alias, field}} -> {select_alias, field}
              {source_alias, field} -> {source_alias, field}
            end)
          end)
        end

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
      Enum.map_reduce(expr.expr, counter, fn {op, kw}, counter ->
        {kw, acc} =
          Enum.map_reduce(kw, counter, fn {field, value}, counter ->
            {value, acc} = prewalk(value, :update, query, expr, counter, adapter)
            {{field_source(source, field), value}, acc}
          end)

        {{op, kw}, acc}
      end)

    {%{expr | expr: inner, params: nil}, acc}
  end

  defp prewalk(kind, query, expr, counter, adapter) do
    {inner, acc} = prewalk(expr.expr, kind, query, expr, counter, adapter)
    {%{expr | expr: inner, params: nil}, acc}
  end

  defp prewalk({:subquery, i}, kind, query, expr, acc, adapter) do
    prewalk_source(Enum.fetch!(expr.subqueries, i), kind, query, expr, acc, adapter)
  end

  defp prewalk({:in, in_meta, [left, {:^, meta, [param]}]}, kind, query, expr, acc, adapter) do
    {left, acc} = prewalk(left, kind, query, expr, acc, adapter)
    {right, acc} = validate_in(meta, expr, param, acc, adapter)
    {{:in, in_meta, [left, right]}, acc}
  end

  defp prewalk({:in, in_meta, [left, {:subquery, _} = right]}, kind, query, expr, acc, adapter) do
    {left, acc} = prewalk(left, kind, query, expr, acc, adapter)
    {right, acc} = prewalk(right, kind, query, expr, acc, adapter)

    case right.query.select.fields do
      [_] ->
        :ok

      _ ->
        error!(
          query,
          "subquery must return a single field in order to be used on the right-side of `in`"
        )
    end

    {{:in, in_meta, [left, right]}, acc}
  end

  defp prewalk({quantifier, meta, [{:subquery, _} = subquery]}, kind, query, expr, acc, adapter)
       when quantifier in [:exists, :any, :all] do
    {subquery, acc} = prewalk(subquery, kind, query, expr, acc, adapter)

    case {quantifier, subquery.query.select.fields} do
      {:exists, _} ->
        :ok

      {_, [_]} ->
        :ok

      _ ->
        error!(
          query,
          "subquery must return a single field in order to be used with #{quantifier}"
        )
    end

    {{quantifier, meta, [subquery]}, acc}
  end

  defp prewalk(
         {:splice, splice_meta, [{:^, meta, [_]}, length]},
         _kind,
         _query,
         _expr,
         acc,
         _adapter
       ) do
    param = {:^, meta, [acc, length]}
    {{:splice, splice_meta, [param]}, acc + length}
  end

  defp prewalk({{:., dot_meta, [left, field]}, meta, []}, kind, query, expr, acc, _adapter) do
    {ix, ix_expr, ix_query} = get_ix!(left, kind, query)
    extra = if kind == :select, do: [type: type!(kind, ix_query, expr, ix, field)], else: []
    field = field_source(get_source!(kind, ix_query, ix), field)
    {{{:., extra ++ dot_meta, [ix_expr, field]}, meta, []}, acc}
  end

  defp prewalk({:^, meta, [ix]}, _kind, _query, _expr, acc, _adapter) when is_integer(ix) do
    {{:^, meta, [acc]}, acc + 1}
  end

  defp prewalk({:type, _, [arg, type]}, kind, query, expr, acc, adapter) do
    {arg, acc} = prewalk(arg, kind, query, expr, acc, adapter)
    type = field_type!(kind, query, expr, type, true)
    {%Ecto.Query.Tagged{value: arg, tag: type, type: Ecto.Type.type(type)}, acc}
  end

  defp prewalk({:json_extract_path, meta, [json_field, path]}, kind, query, expr, acc, _adapter) do
    {{:., dot_meta, [left, field]}, expr_meta, []} = json_field
    {ix, ix_expr, ix_query} = get_ix!(left, kind, query)

    type = type!(kind, ix_query, expr, ix, field)
    validate_json_path!(path, field, type)

    field_source = kind |> get_source!(ix_query, ix) |> field_source(field)

    json_field = {{:., dot_meta, [ix_expr, field_source]}, expr_meta, []}
    {{:json_extract_path, meta, [json_field, path]}, acc}
  end

  defp prewalk({:selected_as, [], [name]}, _kind, query, _expr, acc, _adapter) do
    name = selected_as!(query.select.aliases, name)
    {{:selected_as, [], [name]}, acc}
  end

  defp prewalk(%Ecto.Query.Tagged{value: v, type: type} = tagged, kind, query, expr, acc, adapter) do
    if Ecto.Type.base?(type) do
      {tagged, acc}
    else
      type = field_type!(kind, query, expr, type)

      with {:ok, type} <- normalize_param(kind, type, v),
           {:ok, value} <- dump_param(adapter, type, v) do
        # We cannot encode binary/uuid in queries because they would emit
        # invalid queries with binary parts in them. In theory, we could
        # wrap them in Ecto.Query.Tagged, but a tagged UUID would most
        # likely wrap its string representation, not its binary one.
        # So it is best to be consistent and not support query-dumping of
        # non-base types.
        if is_binary(value) and Ecto.Type.type(type) in [:binary_id, :binary, :uuid] do
          error =
            "cannot encode value `#{inspect(v)}` of type `#{inspect(type)}` within a query, please interpolate (using ^) instead"

          error!(query, expr, error)
        else
          {value, acc}
        end
      else
        {:error, error} ->
          error =
            error <>
              ". Or the value is incompatible or it must be " <>
              "interpolated (using ^) so it may be cast accordingly"

          error!(query, expr, error)
      end
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

  defp selected_as!(select_aliases, name) do
    case select_aliases do
      %{^name => _} ->
        name

      _ ->
        raise ArgumentError,
              "invalid alias: `#{inspect(name)}`. Use `selected_as/2` to define aliases in the outer most `select` expression."
    end
  end

  defp validate_in(meta, expr, param, acc, adapter) do
    {v, t} = Enum.fetch!(expr.params, param)
    length = length(v)

    case adapter.dumpers(t, t) do
      [{:in, _} | _] -> {{:^, meta, [acc, length]}, acc + length}
      _ -> {{:^, meta, [acc, length]}, acc + 1}
    end
  end

  defp normalize_select(%{select: nil} = query, _keep_literals?) do
    {query, nil}
  end

  defp normalize_select(query, keep_literals?) do
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
      collect_fields(expr, [], :none, query, take, keep_literals?, %{})

    {fields, preprocess, from} =
      case from do
        {from_expr, from_source, from_fields} ->
          {assoc_exprs, assoc_fields} = collect_assocs([], [], query, tag, from_take, assocs)
          fields = from_fields ++ Enum.reverse(assoc_fields, Enum.reverse(fields))
          preprocess = [from_expr | Enum.reverse(assoc_exprs)]
          {fields, preprocess, {from_tag, from_source}}

        :none when preloads != [] or assocs != [] ->
          error!(
            query,
            "the binding used in `from` must be selected in `select` when using `preload`"
          )

        :none ->
          {Enum.reverse(fields), [], :none}
      end

    select = %{
      preprocess: preprocess,
      postprocess: postprocess,
      take: from_take,
      assocs: assocs,
      from: from
    }

    {put_in(query.select.fields, fields), select}
  end

  # Handling of source

  # The idea of collect_fields is to collect all fields used in select.
  # However, special care is taken in for `from`. Because `from` is used
  # earlier in assoc/preloads, any operation done on `from` is separately
  # collected in the `from` information. Then, everything else refers to
  # the preprocessed `from` as `{:source, :from}`.

  defp collect_fields(
         {:merge, _, [left, right]},
         fields,
         from,
         query,
         take,
         keep_literals?,
         _drop
       ) do
    case collect_fields(left, fields, from, query, take, keep_literals?, %{}) do
      {{:source, :from}, fields, left_from} ->
        {right, right_fields, _} =
          collect_fields(right, [], left_from, query, take, keep_literals?, %{})

        {from_expr, from_source, from_fields} = left_from

        from =
          {{:merge, from_expr, right}, from_source, from_fields ++ Enum.reverse(right_fields)}

        {{:source, :from}, fields, from}

      {left, left_fields, left_from} ->
        {right, right_fields, right_from} =
          collect_fields(right, left_fields, left_from, query, take, keep_literals?, %{})

        {{:merge, left, right}, right_fields, right_from}
    end
  end

  defp collect_fields({:&, _, [0]}, fields, :none, query, take, _keep_literals?, drop) do
    {expr, taken} = source_take!(:select, query, take, 0, 0, drop)
    {{:source, :from}, fields, {{:source, :from}, expr, taken}}
  end

  defp collect_fields({:&, _, [0]}, fields, from, _query, _take, _keep_literals?, _drop) do
    {{:source, :from}, fields, from}
  end

  defp collect_fields({:&, _, [ix]}, fields, from, query, take, _keep_literals?, drop) do
    {expr, taken} = source_take!(:select, query, take, ix, ix, drop)
    {expr, Enum.reverse(taken, fields), from}
  end

  # Expression handling

  defp collect_fields(
         {agg, _, [{{:., dot_meta, [{:&, _, [_]}, _]}, _, []} | _]} = expr,
         fields,
         from,
         _query,
         _take,
         _keep_literals?,
         _drop
       )
       when agg in @aggs do
    type =
      case agg do
        :count -> :integer
        :row_number -> :integer
        :rank -> :integer
        :dense_rank -> :integer
        :ntile -> :integer
        # If it is possible to upcast, we do it, otherwise keep the DB value.
        # For example, an average of integers will return a decimal, which can't be cast
        # as an integer. But an average of "moneys" should be upcast.
        _ -> {:try, Keyword.fetch!(dot_meta, :type)}
      end

    {{:value, type}, [expr | fields], from}
  end

  defp collect_fields(
         {:filter, _, [call, _]} = expr,
         fields,
         from,
         query,
         take,
         keep_literals?,
         _drop
       ) do
    case call do
      {agg, _, _} when agg in @aggs ->
        :ok

      {:fragment, _, [_ | _]} ->
        :ok

      _ ->
        error!(
          query,
          "filter(...) expects the first argument to be an aggregate expression, got: `#{Macro.to_string(expr)}`"
        )
    end

    {type, _, _} = collect_fields(call, fields, from, query, take, keep_literals?, %{})
    {type, [expr | fields], from}
  end

  defp collect_fields(
         {:coalesce, _, [left, right]} = expr,
         fields,
         from,
         query,
         take,
         _keep_literals?,
         _drop
       ) do
    {left_type, _, _} = collect_fields(left, fields, from, query, take, true, %{})
    {right_type, _, _} = collect_fields(right, fields, from, query, take, true, %{})

    type = if left_type == right_type, do: left_type, else: {:value, :any}
    {type, [expr | fields], from}
  end

  defp collect_fields(
         {:over, _, [call, window]} = expr,
         fields,
         from,
         query,
         take,
         keep_literals?,
         _drop
       ) do
    if is_atom(window) and not Keyword.has_key?(query.windows, window) do
      error!(query, "unknown window #{inspect(window)} given to over/2")
    end

    {type, _, _} = collect_fields(call, fields, from, query, take, keep_literals?, %{})
    {type, [expr | fields], from}
  end

  defp collect_fields(
         {{:., dot_meta, [{:&, _, [_]}, _]}, _, []} = expr,
         fields,
         from,
         _query,
         _take,
         _keep_literals?,
         _drop
       ) do
    {{:value, Keyword.fetch!(dot_meta, :type)}, [expr | fields], from}
  end

  defp collect_fields({left, right}, fields, from, query, take, keep_literals?, _drop) do
    {args, fields, from} =
      collect_args([left, right], fields, from, query, take, keep_literals?, [])

    {{:tuple, args}, fields, from}
  end

  defp collect_fields({:{}, _, args}, fields, from, query, take, keep_literals?, _drop) do
    {args, fields, from} = collect_args(args, fields, from, query, take, keep_literals?, [])
    {{:tuple, args}, fields, from}
  end

  defp collect_fields(
         {:%{}, _, [{:|, _, [data, args]}]},
         fields,
         from,
         query,
         take,
         keep_literals?,
         _drop
       ) do
    drop = Map.new(args, fn {key, _} -> {key, nil} end)
    {data, fields, from} = collect_fields(data, fields, from, query, take, keep_literals?, drop)
    {args, fields, from} = collect_kv(args, fields, from, query, take, keep_literals?, [])
    {{:map, data, args}, fields, from}
  end

  defp collect_fields({:%{}, _, args}, fields, from, query, take, keep_literals?, _drop) do
    {args, fields, from} = collect_kv(args, fields, from, query, take, keep_literals?, [])
    {{:map, args}, fields, from}
  end

  defp collect_fields(
         {:%, _, [name, {:%{}, _, [{:|, _, [data, args]}]}]},
         fields,
         from,
         query,
         take,
         keep_literals?,
         _drop
       ) do
    drop = Map.new(args, fn {key, _} -> {key, nil} end)
    {data, fields, from} = collect_fields(data, fields, from, query, take, keep_literals?, drop)
    {args, fields, from} = collect_kv(args, fields, from, query, take, keep_literals?, [])
    struct!(name, args)
    {{:struct, name, data, args}, fields, from}
  end

  defp collect_fields(
         {:%, _, [name, {:%{}, _, args}]},
         fields,
         from,
         query,
         take,
         keep_literals?,
         _drop
       ) do
    {args, fields, from} = collect_kv(args, fields, from, query, take, keep_literals?, [])
    struct!(name, args)
    {{:struct, name, args}, fields, from}
  end

  defp collect_fields(
         {:date_add, _, [arg | _]} = expr,
         fields,
         from,
         query,
         take,
         keep_literals?,
         _drop
       ) do
    case collect_fields(arg, fields, from, query, take, keep_literals?, %{}) do
      {{:value, :any}, _, _} -> {{:value, :date}, [expr | fields], from}
      {type, _, _} -> {type, [expr | fields], from}
    end
  end

  defp collect_fields(
         {:datetime_add, _, [arg | _]} = expr,
         fields,
         from,
         query,
         take,
         keep_literals?,
         _drop
       ) do
    case collect_fields(arg, fields, from, query, take, keep_literals?, %{}) do
      {{:value, :any}, _, _} -> {{:value, :naive_datetime}, [expr | fields], from}
      {type, _, _} -> {type, [expr | fields], from}
    end
  end

  defp collect_fields(args, fields, from, query, take, keep_literals?, _drop)
       when is_list(args) do
    {args, fields, from} = collect_args(args, fields, from, query, take, keep_literals?, [])
    {{:list, args}, fields, from}
  end

  defp collect_fields(expr, fields, from, _query, _take, true, _drop) when is_binary(expr) do
    {{:value, :binary}, [expr | fields], from}
  end

  defp collect_fields(expr, fields, from, _query, _take, true, _drop) when is_integer(expr) do
    {{:value, :integer}, [expr | fields], from}
  end

  defp collect_fields(expr, fields, from, _query, _take, true, _drop) when is_float(expr) do
    {{:value, :float}, [expr | fields], from}
  end

  defp collect_fields(expr, fields, from, _query, _take, true, _drop) when is_boolean(expr) do
    {{:value, :boolean}, [expr | fields], from}
  end

  defp collect_fields(nil, fields, from, _query, _take, true, _drop) do
    {{:value, :any}, [nil | fields], from}
  end

  defp collect_fields(expr, fields, from, _query, _take, _keep_literals?, _drop)
       when is_atom(expr) do
    {expr, fields, from}
  end

  defp collect_fields(expr, fields, from, _query, _take, false, _drop)
       when is_binary(expr) or is_number(expr) do
    {expr, fields, from}
  end

  defp collect_fields(
         %Ecto.Query.Tagged{tag: tag} = expr,
         fields,
         from,
         _query,
         _take,
         _keep_literals?,
         _drop
       ) do
    {{:value, tag}, [expr | fields], from}
  end

  defp collect_fields({op, _, [_]} = expr, fields, from, _query, _take, _keep_literals?, _drop)
       when op in ~w(not is_nil)a do
    {{:value, :boolean}, [expr | fields], from}
  end

  defp collect_fields({op, _, [_, _]} = expr, fields, from, _query, _take, _keep_literals?, _drop)
       when op in ~w(< > <= >= == != and or like ilike)a do
    {{:value, :boolean}, [expr | fields], from}
  end

  defp collect_fields(
         {:selected_as, _, [select_expr, name]},
         fields,
         from,
         query,
         take,
         keep_literals?,
         _drop
       ) do
    {type, _, _} = collect_fields(select_expr, fields, from, query, take, keep_literals?, %{})
    {type, [{name, select_expr} | fields], from}
  end

  defp collect_fields(expr, fields, from, _query, _take, _keep_literals?, _drop) do
    {{:value, :any}, [expr | fields], from}
  end

  defp collect_kv([{key, value} | elems], fields, from, query, take, keep_literals?, acc) do
    {key, fields, from} = collect_fields(key, fields, from, query, take, keep_literals?, %{})
    {value, fields, from} = collect_fields(value, fields, from, query, take, keep_literals?, %{})
    collect_kv(elems, fields, from, query, take, keep_literals?, [{key, value} | acc])
  end

  defp collect_kv([], fields, from, _query, _take, _keep_literals?, acc) do
    {Enum.reverse(acc), fields, from}
  end

  defp collect_args([elem | elems], fields, from, query, take, keep_literals?, acc) do
    {elem, fields, from} = collect_fields(elem, fields, from, query, take, keep_literals?, %{})
    collect_args(elems, fields, from, query, take, keep_literals?, [elem | acc])
  end

  defp collect_args([], fields, from, _query, _take, _keep_literals?, acc) do
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
          error!(
            query,
            "association `#{field}` is being set to binding at position #{index} " <>
              "and at position #{other_index} at the same time"
          )
      end)
    end)
    |> Map.to_list()
  end

  defp collect_assocs(exprs, fields, query, tag, take, [{assoc, {ix, children}} | tail]) do
    to_take = get_preload_source!(query, ix)
    {fetch, take_children} = fetch_assoc(tag, take, assoc)
    {expr, taken} = take!(to_take, query, fetch, assoc, ix, %{})
    exprs = [expr | exprs]
    fields = Enum.reverse(taken, fields)
    {exprs, fields} = collect_assocs(exprs, fields, query, tag, take_children, children)
    {exprs, fields} = collect_assocs(exprs, fields, query, tag, take, tail)
    {exprs, fields}
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

  defp source_take!(kind, query, take, field, ix, drop) do
    source = get_source!(kind, query, ix)
    take!(source, query, Access.fetch(take, field), field, ix, drop)
  end

  defp take!(source, query, fetched, field, ix, drop) do
    case {fetched, source} do
      {{:ok, {:struct, _}}, {:fragment, _, _}} ->
        error!(query, "it is not possible to return a struct subset of a fragment")

      {{:ok, {:struct, fields}}, %Ecto.SubQuery{select: select}} ->
        subquery_select_fields(select, fields, ix, query)

      {{:ok, {_, []}}, {_, _, _}} ->
        error!(
          query,
          "at least one field must be selected for binding `#{field}`, got an empty list"
        )

      {{:ok, {:struct, _}}, {_, nil, _}} ->
        error!(query, "struct/2 in select expects a source with a schema")

      {{:ok, {kind, fields}}, {source, schema, prefix}} when is_binary(source) ->
        dumper = if schema, do: schema.__schema__(:dump), else: %{}
        schema = if kind == :map, do: nil, else: schema
        {types, fields} = select_dump(List.wrap(fields), dumper, ix, drop)
        {{:source, {source, schema}, prefix || query.prefix, types}, fields}

      {{:ok, {_, fields}}, _} ->
        {{:map, Enum.map(fields, &{&1, {:value, :any}})},
         Enum.map(fields, &select_field(&1, ix, :always))}

      {:error, {:fragment, _, _}} ->
        {{:value, :map}, [{:&, [], [ix]}]}

      {:error, {:values, _, [types, _]}} ->
        fields = Keyword.keys(types)

        dumper =
          types
          |> Enum.map(fn {field, type} -> {field, {field, type, :always}} end)
          |> Enum.into(%{})

        {types, fields} = select_dump(fields, dumper, ix, drop)
        {{:source, :values, nil, types}, fields}

      {:error, {_, nil, _}} ->
        {{:value, :map}, [{:&, [], [ix]}]}

      {:error, {source, schema, prefix}} ->
        {types, fields} =
          select_dump(schema.__schema__(:query_fields), schema.__schema__(:dump), ix, drop)

        {{:source, {source, schema}, prefix || query.prefix, types}, fields}

      {:error, %Ecto.SubQuery{select: select}} ->
        fields = subquery_source_fields(select)
        {select, Enum.map(fields, &select_field(&1, ix, :always))}
    end
  end

  defp select_dump(fields, dumper, ix, drop) do
    fields
    |> Enum.reverse()
    |> Enum.reduce({[], []}, fn
      field, {types, exprs} when is_atom(field) and not is_map_key(drop, field) ->
        {source, type, writable} = Map.get(dumper, field, {field, :any, :always})
        {[{field, type} | types], [select_field(source, ix, writable) | exprs]}

      _field, acc ->
        acc
    end)
  end

  defp subquery_select_fields(select, requested_fields, ix, query) do
    available_fields = subquery_source_fields(select)
    requested_fields = List.wrap(requested_fields)

    schema =
      case select do
        {:source, {_, schema}, _, _} when not is_nil(schema) -> schema

        _ ->
          error!(query, "it is not possible to return a struct subset of a subquery that does not return a schema struct")
      end

    types =
      Enum.map(requested_fields, fn field ->
        case subquery_type_for(select, field) do
          {:ok, type} ->
            {field, type}

          :error ->
            error!(query, "field `#{field}` in struct/2 is not available in the subquery. " <>
                         "Subquery only returns fields: #{inspect(available_fields)}")
        end
      end)

    field_exprs = Enum.map(requested_fields, &select_field(&1, ix, :always))

    {{:source, {nil, schema}, nil, types}, field_exprs}
  end

  defp select_field(field, ix, writable) do
    {{:., [writable: writable], [{:&, [], [ix]}, field]}, [], []}
  end

  defp get_ix!({:&, _, [ix]} = expr, _kind, query) do
    {ix, expr, query}
  end

  defp get_ix!({:as, meta, [as]}, _kind, query) do
    case query.aliases do
      %{^as => ix} -> {ix, {:&, meta, [ix]}, query}
      %{} -> error!(query, "could not find named binding `as(#{inspect(as)})`")
    end
  end

  defp get_ix!({:parent_as, meta, [as]}, kind, query) do
    case query.aliases[@parent_as] do
      %{aliases: %{^as => ix}, sources: sources} = query ->
        if kind == :select and not (ix < tuple_size(sources)) do
          error!(
            query,
            "the parent_as in a subquery select used as a join can only access the `from` binding"
          )
        else
          {ix, {:parent_as, [], [as]}, query}
        end

      %{} = parent ->
        get_ix!({:parent_as, meta, [as]}, kind, parent)

      nil ->
        error!(query, "could not find named binding `parent_as(#{inspect(as)})`")
    end
  end

  defp get_source!(where, %{sources: sources} = query, ix) do
    elem(sources, ix)
  rescue
    ArgumentError ->
      error!(
        query,
        "invalid query has specified more bindings than bindings available " <>
          "in `#{where}` (look for `unknown_binding!` in the printed query below)"
      )
  end

  defp get_preload_source!(query, ix) do
    case get_source!(:preload, query, ix) do
      {source, schema, _} = all when is_binary(source) and schema != nil ->
        all

      %Ecto.SubQuery{select: {:source, {source, schema}, _, _}} = subquery
      when is_binary(source) and schema != nil ->
        subquery

      _ ->
        error!(
          query,
          "can only preload sources with a schema " <>
            "(fragments, binaries, and subqueries that do not select a from/join schema are not supported)"
        )
    end
  end

  @doc """
  Puts the prefix given via `opts` into the given query, if available.
  """
  def attach_prefix(%{prefix: nil} = query, opts) when is_list(opts) do
    case Keyword.fetch(opts, :prefix) do
      {:ok, prefix} ->
        %{query | prefix: prefix}

      :error ->
        query
    end
  end

  def attach_prefix(%{prefix: nil} = query, %{prefix: prefix}) do
    %{query | prefix: prefix}
  end

  def attach_prefix(query, _), do: query

  ## Helpers

  @all_exprs [
    with_cte: :with_ctes,
    distinct: :distinct,
    select: :select,
    from: :from,
    join: :joins,
    where: :wheres,
    group_by: :group_bys,
    having: :havings,
    windows: :windows,
    combination: :combinations,
    order_by: :order_bys,
    limit: :limit,
    offset: :offset
  ]

  # Although joins come before updates in the actual query,
  # the on fields are moved to where, so they effectively
  # need to come later for MySQL. This means subqueries
  # with parameters are not supported as a join on MySQL.
  # The only way to address it is by splitting how join
  # and their on expressions are processed.
  @update_all_exprs [
    with_cte: :with_ctes,
    from: :from,
    update: :updates,
    join: :joins,
    where: :wheres,
    select: :select
  ]

  @delete_all_exprs [
    with_cte: :with_ctes,
    from: :from,
    join: :joins,
    where: :wheres,
    select: :select
  ]

  # Traverse all query components with expressions.
  # Therefore from, preload, assocs and lock are not traversed.
  defp traverse_exprs(query, operation, acc, fun) do
    exprs =
      case operation do
        :all -> @all_exprs
        :insert_all -> @all_exprs
        :update_all -> @update_all_exprs
        :delete_all -> @delete_all_exprs
      end

    Enum.reduce(exprs, {query, acc}, fn {kind, key}, {query, acc} ->
      {traversed, acc} = fun.(kind, query, Map.fetch!(query, key), acc)
      {%{query | key => traversed}, acc}
    end)
  end

  defp field_type!(kind, query, expr, type, allow_virtuals? \\ false)

  defp field_type!(kind, query, expr, {composite, {ix, field}}, allow_virtuals?)
       when is_integer(ix) do
    {composite, type!(kind, query, expr, ix, field, allow_virtuals?)}
  end

  defp field_type!(
         kind,
         query,
         expr,
         {composite, {{bind_kind, _, [_]} = bind_expr, field}},
         allow_virtuals?
       )
       when bind_kind in [:as, :parent_as] do
    {ix, _, ix_query} = get_ix!(bind_expr, kind, query)
    {composite, type!(kind, ix_query, expr, ix, field, allow_virtuals?)}
  end

  defp field_type!(kind, query, expr, {{bind_kind, _, [_]} = bind_expr, field}, allow_virtuals?)
       when bind_kind in [:as, :parent_as] do
    {ix, _, ix_query} = get_ix!(bind_expr, kind, query)
    type!(kind, ix_query, expr, ix, field, allow_virtuals?)
  end

  defp field_type!(kind, query, expr, {ix, field}, allow_virtuals?) when is_integer(ix) do
    type!(kind, query, expr, ix, field, allow_virtuals?)
  end

  defp field_type!(_kind, _query, _expr, type, _) do
    type
  end

  defp type!(kind, query, expr, schema, field, allow_virtuals? \\ false)

  defp type!(_kind, _query, _expr, nil, _field, _allow_virtuals?), do: :any

  defp type!(_kind, _query, _expr, _ix, field, _allow_virtuals?) when is_binary(field), do: :any

  defp type!(kind, query, expr, ix, field, allow_virtuals?) when is_integer(ix) do
    case get_source!(kind, query, ix) do
      {:fragment, _, _} ->
        :any

      {:values, _, [types, _]} ->
        case Keyword.fetch(types, field) do
          {:ok, type} ->
            type

          :error ->
            error!(query, expr, "field `#{field}` in `#{kind}` does not exist in values list")
        end

      {_, schema, _} ->
        type!(kind, query, expr, schema, field, allow_virtuals?)

      %Ecto.SubQuery{select: select} ->
        case subquery_type_for(select, field) do
          {:ok, type} -> type
          :error -> error!(query, expr, "field `#{field}` does not exist in subquery")
        end
    end
  end

  defp type!(kind, query, expr, schema, field, allow_virtuals?) when is_atom(schema) do
    cond do
      type = schema.__schema__(:type, field) ->
        type

      type = allow_virtuals? && schema.__schema__(:virtual_type, field) ->
        type

      Map.has_key?(schema.__struct__(), field) ->
        case schema.__schema__(:association, field) do
          %Ecto.Association.BelongsTo{owner_key: owner_key} ->
            error!(
              query,
              expr,
              "field `#{field}` in `#{kind}` is an association in schema #{inspect(schema)}. " <>
                "Did you mean to use `#{owner_key}`?"
            )

          %_{} ->
            error!(
              query,
              expr,
              "field `#{field}` in `#{kind}` is an association in schema #{inspect(schema)}"
            )

          _ ->
            error!(
              query,
              expr,
              "field `#{field}` in `#{kind}` is a virtual field in schema #{inspect(schema)}"
            )
        end

      true ->
        hint = closest_fields_hint(field, schema)

        error!(
          query,
          expr,
          "field `#{field}` in `#{kind}` does not exist in schema #{inspect(schema)}",
          hint
        )
    end
  end

  defp closest_fields_hint(input, schema) do
    input_string = Atom.to_string(input)

    schema.__schema__(:fields)
    |> Enum.map(fn field -> {field, String.jaro_distance(input_string, Atom.to_string(field))} end)
    |> Enum.filter(fn {_field, score} -> score >= 0.77 end)
    |> Enum.sort(&(elem(&1, 0) >= elem(&2, 0)))
    |> Enum.take(5)
    |> Enum.map(&elem(&1, 0))
    |> case do
      [] ->
        nil

      [suggestion] ->
        "Did you mean `#{suggestion}`?"

      suggestions ->
        Enum.reduce(suggestions, "Did you mean one of: \n", fn suggestion, acc ->
          acc <> "\n      * `#{suggestion}`"
        end)
    end
  end

  defp normalize_param(_kind, {:out, {:array, type}}, _value) do
    {:ok, type}
  end

  defp normalize_param(_kind, {:out, :any}, _value) do
    {:ok, :any}
  end

  defp normalize_param(kind, {:out, other}, value) do
    {:error,
     "value `#{inspect(value)}` in `#{kind}` expected to be part of an array " <>
       "but matched type is #{inspect(other)}"}
  end

  defp normalize_param(_kind, type, _value) do
    {:ok, type}
  end

  defp cast_param(kind, type, v) do
    case Ecto.Type.cast(type, v) do
      {:ok, v} ->
        {:ok, v}

      :error ->
        {:error,
         "value `#{inspect(v)}` in `#{kind}` cannot be cast to type #{Ecto.Type.format(type)}"}

      {:error, _meta} ->
        {:error,
         "value `#{inspect(v)}` in `#{kind}` cannot be cast to type #{Ecto.Type.format(type)}"}

      other ->
        raise "expected #{inspect(type)}.cast/1 to return {:ok, v}, :error, or {:error, meta}" <>
                ", got: #{inspect(other)}"
    end
  end

  defp dump_param(adapter, type, v) do
    case Ecto.Type.adapter_dump(adapter, type, v) do
      {:ok, v} ->
        {:ok, v}

      :error ->
        {:error, "value `#{inspect(v)}` cannot be dumped to type #{Ecto.Type.format(type)}"}
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

  defp cte_fields([key | rest_keys], [{key, select_expr} | rest_fields], aliases) do
    [{key, select_expr} | cte_fields(rest_keys, rest_fields, aliases)]
  end

  defp cte_fields([key | rest_keys], [field | rest_fields], aliases) do
    if Map.has_key?(aliases, key) do
      raise ArgumentError,
            "the alias, #{inspect(key)}, provided to `selected_as/2` conflicts" <>
              "with the CTE's automatic aliasing. When using `selected_as/2`" <>
              "inside of a CTE, you must ensure it does not conflict with any of the other" <>
              "field names"
    end

    {key, field} =
      case field do
        {alias, select_expr} -> {alias, select_expr}
        field -> {key, field}
      end

    [{key, field} | cte_fields(rest_keys, rest_fields, aliases)]
  end

  defp cte_fields([], [], _aliases), do: []

  defp assert_update!(%Ecto.Query{updates: updates} = query, operation) do
    dumper = dumper_for_update(query)

    changes =
      Enum.reduce(updates, %{}, fn update, acc ->
        Enum.reduce(update.expr, acc, fn {_op, kw}, acc ->
          Enum.reduce(kw, acc, fn {k, v}, acc ->
            if Map.has_key?(acc, k) do
              error!(query, "duplicate field `#{k}` for `#{operation}`")
            end

            case dumper do
              %{^k => {_, _, :always}} -> :ok
              %{} -> error!(query, "cannot update non-updatable field `#{inspect(k)}`")
              nil -> :ok
            end

            Map.put(acc, k, v)
          end)
        end)
      end)

    if changes == %{} do
      error!(query, "`#{operation}` requires at least one field to be updated")
    end
  end

  defp assert_no_update!(query, operation) do
    case query do
      %Ecto.Query{updates: []} ->
        query

      _ ->
        error!(query, "`#{operation}` does not allow `update` expressions")
    end
  end

  defp assert_only_filter_expressions!(query, operation) do
    case query do
      %Ecto.Query{
        order_bys: [],
        limit: nil,
        offset: nil,
        group_bys: [],
        havings: [],
        preloads: [],
        assocs: [],
        distinct: nil,
        lock: nil,
        windows: [],
        combinations: []
      } ->
        query

      _ when operation == :delete_all ->
        error!(
          query,
          "`#{operation}` allows only `with_cte`, `where`, `select`, and `join` expressions. " <>
            "You can exclude unwanted expressions from a query by using " <>
            "Ecto.Query.exclude/2. Error found"
        )

      _ ->
        error!(
          query,
          "`#{operation}` allows only `with_cte`, `where` and `join` expressions. " <>
            "You can exclude unwanted expressions from a query by using " <>
            "Ecto.Query.exclude/2. Error found"
        )
    end
  end

  defp dumper_for_update(query) do
    case get_source!(:updates, query, 0) do
      {source, schema, _} when is_binary(source) and schema != nil ->
        schema.__schema__(:dump)

      _ ->
        nil
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

  defp error!(query, expr, message, hint) do
    raise Ecto.QueryError,
      message: message,
      query: query,
      file: expr.file,
      line: expr.line,
      hint: hint
  end
end
