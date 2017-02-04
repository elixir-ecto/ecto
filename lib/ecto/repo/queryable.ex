defmodule Ecto.Repo.Queryable do
  # The module invoked by user defined repos
  # for query related functionality.
  @moduledoc false

  alias Ecto.Query
  alias Ecto.Queryable
  alias Ecto.Query.Planner
  alias Ecto.Query.SelectExpr

  require Ecto.Query

  def transaction(adapter, repo, fun, opts) when is_function(fun, 0) do
    adapter.transaction(repo, opts, fun)
  end

  def transaction(adapter, repo, %Ecto.Multi{} = multi, opts) do
    wrap   = &adapter.transaction(repo, opts, &1)
    return = &adapter.rollback(repo, &1)

    case Ecto.Multi.__apply__(multi, repo, wrap, return) do
      {:ok, values} ->
        {:ok, values}
      {:error, {key, error_value, values}} ->
        {:error, key, error_value, values}
    end
  end

  def all(repo, adapter, queryable, opts) when is_list(opts) do
    query =
      queryable
      |> Ecto.Queryable.to_query
      |> Ecto.Query.Planner.returning(true)
      |> attach_prefix(opts)
    execute(:all, repo, adapter, query, opts) |> elem(1)
  end

  def stream(repo, adapter, queryable, opts) when is_list(opts) do
    query =
      queryable
      |> Ecto.Queryable.to_query
      |> Ecto.Query.Planner.returning(true)
      |> attach_prefix(opts)
    stream(:all, repo, adapter, query, opts)
  end

  def get(repo, adapter, queryable, id, opts) do
    one(repo, adapter, query_for_get(repo, queryable, id), opts)
  end

  def get!(repo, adapter, queryable, id, opts) do
    one!(repo, adapter, query_for_get(repo, queryable, id), opts)
  end

  def get_by(repo, adapter, queryable, clauses, opts) do
    one(repo, adapter, query_for_get_by(repo, queryable, clauses), opts)
  end

  def get_by!(repo, adapter, queryable, clauses, opts) do
    one!(repo, adapter, query_for_get_by(repo, queryable, clauses), opts)
  end

  def aggregate(repo, adapter, queryable, aggregate, field, opts) do
    one!(repo, adapter, query_for_aggregate(queryable, aggregate, field), opts)
  end

  def one(repo, adapter, queryable, opts) do
    case all(repo, adapter, queryable, opts) do
      [one] -> one
      []    -> nil
      other -> raise Ecto.MultipleResultsError, queryable: queryable, count: length(other)
    end
  end

  def one!(repo, adapter, queryable, opts) do
    case all(repo, adapter, queryable, opts) do
      [one] -> one
      []    -> raise Ecto.NoResultsError, queryable: queryable
      other -> raise Ecto.MultipleResultsError, queryable: queryable, count: length(other)
    end
  end

  def update_all(repo, adapter, queryable, [], opts) when is_list(opts) do
    update_all(repo, adapter, queryable, opts)
  end

  def update_all(repo, adapter, queryable, updates, opts) when is_list(opts) do
    query = Query.from queryable, update: ^updates
    update_all(repo, adapter, query, opts)
  end

  defp update_all(repo, adapter, queryable, opts) do
    query =
      queryable
      |> Ecto.Queryable.to_query
      |> Ecto.Query.Planner.assert_no_select!(:update_all)
      |> Ecto.Query.Planner.returning(opts[:returning] || false)
      |> attach_prefix(opts)
    execute(:update_all, repo, adapter, query, opts)
  end

  def delete_all(repo, adapter, queryable, opts) when is_list(opts) do
    query =
      queryable
      |> Ecto.Queryable.to_query
      |> Ecto.Query.Planner.assert_no_select!(:delete_all)
      |> Ecto.Query.Planner.returning(opts[:returning] || false)
      |> attach_prefix(opts)
    execute(:delete_all, repo, adapter, query, opts)
  end

  ## Helpers

  defp attach_prefix(query, opts) do
    case Keyword.fetch(opts, :prefix) do
      {:ok, prefix} -> %{query | prefix: prefix}
      :error -> query
    end
  end

  defp execute(operation, repo, adapter, query, opts) when is_list(opts) do
    {meta, prepared, params} = Planner.query(query, operation, repo, adapter, 0)

    case meta do
      %{fields: nil} ->
        adapter.execute(repo, meta, prepared, params, nil, opts)
      %{select: select, fields: fields, prefix: prefix, take: take,
        sources: sources, assocs: assocs, preloads: preloads} ->
        preprocess    = preprocess(prefix, sources, adapter)
        {count, rows} = adapter.execute(repo, meta, prepared, params, preprocess, opts)
        postprocess   = postprocess(select, fields, take)
        {_, take_0}   = Map.get(take, 0, {:any, %{}})
        {count,
          rows
          |> Ecto.Repo.Assoc.query(assocs, sources)
          |> Ecto.Repo.Preloader.query(repo, preloads, take_0, postprocess, opts)}
    end
  end

  defp stream(operation, repo, adapter, query, opts) do
    {meta, prepared, params} = Planner.query(query, operation, repo, adapter, 0)

    case meta do
      %{fields: nil} ->
        adapter.stream(repo, meta, prepared, params, nil, opts)
        |> Stream.flat_map(fn({_, nil}) -> [] end)
      %{select: select, fields: fields, prefix: prefix, take: take,
        sources: sources, assocs: assocs, preloads: preloads} ->
        preprocess    = preprocess(prefix, sources, adapter)
        stream        = adapter.stream(repo, meta, prepared, params, preprocess, opts)
        postprocess   = postprocess(select, fields, take)
        {_, take_0}   = Map.get(take, 0, {:any, %{}})

        Stream.flat_map(stream, fn({_, rows}) ->
          rows
          |> Ecto.Repo.Assoc.query(assocs, sources)
          |> Ecto.Repo.Preloader.query(repo, preloads, take_0, postprocess, opts)
        end)
    end
  end

  defp preprocess(prefix, sources, adapter) do
    &preprocess(&1, &2, prefix, &3, sources, adapter)
  end

  defp preprocess({:&, _, [ix, fields, _]}, value, prefix, context, sources, adapter) do
    case elem(sources, ix) do
      {_source, nil} when is_map(value) ->
        value
      {_source, nil} when is_list(value) ->
        load_schemaless(fields, value, %{})
      {source, schema} when is_list(value) ->
        Ecto.Schema.__load__(schema, prefix, source, context, {fields, value},
                             &Ecto.Type.adapter_load(adapter, &1, &2))
      {source, schema} when is_map(value) ->
        Ecto.Schema.__load__(schema, prefix, source, context, value,
                             &Ecto.Type.adapter_load(adapter, &1, &2))
      %Ecto.SubQuery{meta: %{sources: sources, fields: fields, select: select, take: take}} ->
        loaded = load_subquery(fields, value, prefix, context, sources, adapter)
        postprocess(select, fields, take).(loaded)
    end
  end

  defp preprocess({agg, meta, [{{:., _, [{:&, _, [_]}, _]}, _, []}]},
                  value, _prefix, _context, _sources, adapter) when agg in ~w(avg min max sum)a do
    type = Keyword.fetch!(meta, :ecto_type)
    load!(type, value, adapter)
  end

  defp preprocess({{:., _, [{:&, _, [_]}, _]}, meta, []}, value, _prefix, _context, _sources, adapter) do
    type = Keyword.fetch!(meta, :ecto_type)
    load!(type, value, adapter)
  end

  defp preprocess(%Query.Tagged{tag: tag}, value, _prefix, _context, _sources, adapter) do
    load!(tag, value, adapter)
  end

  defp preprocess(_key, value, _prefix, _context, _sources, _adapter) do
    value
  end

  defp load_subquery([{:&, [], [_, _, counter]} = field|fields], values, prefix, context, sources, adapter) do
    {value, values} = Enum.split(values, counter)
    [preprocess(field, value, prefix, context, sources, adapter) |
     load_subquery(fields, values, prefix, context, sources, adapter)]
  end
  defp load_subquery([field|fields], [value|values], prefix, context, sources, adapter) do
    [preprocess(field, value, prefix, context, sources, adapter) |
     load_subquery(fields, values, prefix, context, sources, adapter)]
  end
  defp load_subquery([], [], _prefix, _context, _sources, _adapter) do
    []
  end

  defp load_schemaless([field|fields], [value|values], acc),
    do: load_schemaless(fields, values, Map.put(acc, field, value))
  defp load_schemaless([], [], acc),
    do: acc

  defp load!(type, value, adapter) do
    case Ecto.Type.adapter_load(adapter, type, value) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "cannot load `#{inspect value}` as type #{inspect type}"
    end
  end

  defp postprocess(select, fields, take) do
    # The planner always put the from as the first
    # entry in the query, avoiding fetching it multiple
    # times even if it appears multiple times in the query.
    # So we always need to handle it specially.
    from? = match?([{:&, _, [0, _, _]}|_], fields)
    &postprocess(&1, select, take, from?)
  end

  defp postprocess(row, expr, take, true),
    do: transform_row(expr, take, hd(row), tl(row)) |> elem(0)
  defp postprocess(row, expr, take, false),
    do: transform_row(expr, take, nil, row) |> elem(0)

  defp transform_row({:&, _, [0]}, take, from, values) do
    {convert_to_tag(from, take[0]), values}
  end

  defp transform_row({:&, _, [ix]}, take, _from, [value|values]) do
    {convert_to_tag(value, take[ix]), values}
  end

  defp transform_row({:{}, _, list}, take, from, values) do
    {result, values} = transform_row(list, take, from, values)
    {List.to_tuple(result), values}
  end

  defp transform_row({left, right}, take, from, values) do
    {[left, right], values} = transform_row([left, right], take, from, values)
    {{left, right}, values}
  end

  defp transform_row({:%{}, _, [{:|, _, [data, pairs]}]}, take, from, values) do
    {data, values} = transform_row(data, take, from, values)
    Enum.reduce pairs, {data, values}, fn {k, v}, {data, acc} ->
      {k, acc} = transform_row(k, take, from, acc)
      {v, acc} = transform_row(v, take, from, acc)
      {:maps.update(k, v, data), acc}
    end
  end

  defp transform_row({:%{}, _, pairs}, take, from, values) do
    Enum.reduce pairs, {%{}, values}, fn {k, v}, {map, acc} ->
      {k, acc} = transform_row(k, take, from, acc)
      {v, acc} = transform_row(v, take, from, acc)
      {Map.put(map, k, v), acc}
    end
  end

  defp transform_row(list, take, from, values) when is_list(list) do
    Enum.map_reduce(list, values, &transform_row(&1, take, from, &2))
  end

  defp transform_row(expr, _take, _from, values)
       when is_atom(expr) or is_binary(expr) or is_number(expr) do
    {expr, values}
  end

  defp transform_row(_, _take, _from, [value|values]) do
    {value, values}
  end

  # We only need to worry about the struct -> map scenario.
  # map -> struct is denied during compilation time.
  # map -> map, struct -> struct and map/struct -> any are noop.
  defp convert_to_tag(%{__struct__: _} = value, {:map, fields}),
    do: to_map(value, fields)
  defp convert_to_tag(value, _),
    do: value

  defp to_map(value, fields) when is_list(value) do
    Enum.map(value, &to_map(&1, fields))
  end
  defp to_map(nil, _fields) do
    nil
  end
  defp to_map(value, fields) do
    for field <- fields, into: %{} do
      case field do
        {k, v} -> {k, to_map(Map.fetch!(value, k), List.wrap(v))}
        k -> {k, Map.fetch!(value, k)}
      end
    end
  end

  defp query_for_get(repo, _queryable, nil) do
    raise ArgumentError, "cannot perform #{inspect repo}.get/2 because the given value is nil"
  end

  defp query_for_get(repo, queryable, id) do
    query  = Queryable.to_query(queryable)
    schema = assert_schema!(query)
    case schema.__schema__(:primary_key) do
      [pk] ->
        Query.from(x in query, where: field(x, ^pk) == ^id)
      pks ->
        raise ArgumentError,
          "#{inspect repo}.get/2 requires the schema #{inspect schema} " <>
          "to have exactly one primary key, got: #{inspect pks}"
    end
  end

  defp query_for_get_by(_repo, queryable, clauses) do
    Query.where(queryable, [], ^Enum.to_list(clauses))
  end

  defp query_for_aggregate(queryable, aggregate, field) do
    query = %{Queryable.to_query(queryable) | preloads: [], assocs: []}
    ast   = field(0, field)

    query =
      case query do
        %{group_bys: [_|_]} ->
          raise Ecto.QueryError, message: "cannot aggregate on query with group_by", query: query
        %{distinct: nil, limit: nil, offset: nil} ->
          %{query | order_bys: []}
        _ ->
          select = %SelectExpr{expr: ast, file: __ENV__.file, line: __ENV__.line}
          %{query | select: select}
          |> Query.subquery()
          |> Queryable.Ecto.SubQuery.to_query()
      end

    %{query | select: %SelectExpr{expr: {aggregate, [], [ast]},
                                  file: __ENV__.file, line: __ENV__.line}}
  end

  defp field(ix, field) when is_integer(ix) and is_atom(field) do
    {{:., [], [{:&, [], [ix]}, field]}, [], []}
  end

  defp assert_schema!(%{from: {_source, schema}}) when schema != nil, do: schema
  defp assert_schema!(query) do
    raise Ecto.QueryError,
      query: query,
      message: "expected a from expression with a schema"
  end
end
