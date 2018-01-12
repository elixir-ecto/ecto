defmodule Ecto.Repo.Queryable do
  # The module invoked by user defined repos
  # for query related functionality.
  @moduledoc false

  @dialyzer {:no_opaque, transaction: 4}

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
      %{select: nil} ->
        adapter.execute(repo, meta, prepared, params, nil, opts)
      %{select: select, prefix: prefix, sources: sources, preloads: preloads} ->
        %{preprocess: preprocess, postprocess: postprocess, take: take, assocs: assocs} = select
        all_nil? = tuple_size(sources) != 1
        preprocessor = &preprocess(&1, preprocess, all_nil?, prefix, adapter)
        {count, rows} = adapter.execute(repo, meta, prepared, params, preprocessor, opts)
        postprocessor = postprocessor(postprocess, take, prefix, adapter)

        {count,
          rows
          |> Ecto.Repo.Assoc.query(assocs, sources)
          |> Ecto.Repo.Preloader.query(repo, preloads, take, postprocessor, opts)}
    end
  end

  defp stream(operation, repo, adapter, query, opts) do
    {meta, prepared, params} = Planner.query(query, operation, repo, adapter, 0)

    case meta do
      %{select: nil} ->
        repo
        |> adapter.stream(meta, prepared, params, nil, opts)
        |> Stream.flat_map(fn {_, nil} -> [] end)
      %{select: select, prefix: prefix, sources: sources, preloads: preloads} ->
        %{preprocess: preprocess, postprocess: postprocess, take: take, assocs: assocs} = select
        all_nil? = tuple_size(sources) != 1
        preprocessor = &preprocess(&1, preprocess, all_nil?, prefix, adapter)
        stream = adapter.stream(repo, meta, prepared, params, preprocessor, opts)
        postprocessor = postprocessor(postprocess, take, prefix, adapter)

        Stream.flat_map(stream, fn {_, rows} ->
          rows
          |> Ecto.Repo.Assoc.query(assocs, sources)
          |> Ecto.Repo.Preloader.query(repo, preloads, take, postprocessor, opts)
        end)
    end
  end

  defp preprocess(row, [], _all_nil?, _prefix, _adapter) do
    row
  end
  defp preprocess(row, [{:source, source_schema, fields} | sources], all_nil?, prefix, adapter) do
    {entry, rest} = process_source(source_schema, fields, row, all_nil?, prefix, adapter)
    [entry | preprocess(rest, sources, true, prefix, adapter)]
  end
  defp preprocess(row, [source | sources], all_nil?, prefix, adapter) do
    {entry, rest} = process(row, source, nil, prefix, adapter)
    [entry | preprocess(rest, sources, all_nil?, prefix, adapter)]
  end

  defp postprocessor({:from, :any, postprocess}, _take, prefix, adapter) do
    fn [from | row] ->
      row |> process(postprocess, from, prefix, adapter) |> elem(0)
    end
  end
  defp postprocessor({:from, :map, postprocess}, take, prefix, adapter) do
    fn [from | row] ->
      row |> process(postprocess, to_map(from, take), prefix, adapter) |> elem(0)
    end
  end
  defp postprocessor(postprocess, _take, prefix, adapter) do
    fn row -> row |> process(postprocess, nil, prefix, adapter) |> elem(0) end
  end

  defp process(row, {:merge, left, right}, from, prefix, adapter) do
    {left, row} = process(row, left, from, prefix, adapter)
    {right, row} = process(row, right, from, prefix, adapter)

    data =
      case {left, right} do
        {%{__struct__: struct}, %{__struct__: struct}} ->
          right
          |> Map.from_struct()
          |> Enum.reduce(left, fn {key, value}, acc -> %{acc | key => value} end)
        {_, %{__struct__: _}} ->
          raise ArgumentError, "can only merge with a struct on the right side when both sides " <>
                               "represent the same struct. Left side is #{inspect left} and " <>
                               "right side is #{inspect right}"
        {%{__struct__: _}, %{}} ->
          Enum.reduce(right, left, fn {key, value}, acc -> %{acc | key => value} end)
        {%{}, %{}} ->
          Map.merge(left, right)
        {_, %{}} ->
          raise ArgumentError, "cannot merge because the left side is not a map, got: #{inspect left}"
        {%{}, _} ->
          raise ArgumentError, "cannot merge because the right side is not a map, got: #{inspect right}"
      end

    {data, row}
  end
  defp process(row, {:struct, struct, data, args}, from, prefix, adapter) do
    case process(row, data, from, prefix, adapter) do
      {%{__struct__: ^struct} = data, row} ->
        process_update(data, args, row, from, prefix, adapter)
      {data, _row} ->
        raise BadStructError, struct: struct, term: data
    end
  end
  defp process(row, {:struct, struct, args}, from, prefix, adapter) do
    {fields, row} = process_kv(args, row, from, prefix, adapter)

    case Map.merge(struct.__struct__(), Map.new(fields)) do
      %{__meta__: %Ecto.Schema.Metadata{source: {_, source}} = metadata} = struct ->
        metadata = %{metadata | state: :loaded, source: {prefix, source}}
        {Map.put(struct, :__meta__, metadata), row}
      map ->
        {map, row}
    end
  end
  defp process(row, {:map, data, args}, from, prefix, adapter) do
    {data, row} = process(row, data, from, prefix, adapter)
    process_update(data, args, row, from, prefix, adapter)
  end
  defp process(row, {:map, args}, from, prefix, adapter) do
    {args, row} = process_kv(args, row, from, prefix, adapter)
    {Map.new(args), row}
  end
  defp process(row, {:list, args}, from, prefix, adapter) do
    process_args(args, row, from, prefix, adapter)
  end
  defp process(row, {:tuple, args}, from, prefix, adapter) do
    {args, row} = process_args(args, row, from, prefix, adapter)
    {List.to_tuple(args), row}
  end
  defp process(row, {:source, :from}, from, _prefix, _adapter) do
    {from, row}
  end
  defp process(row, {:source, source_schema, fields}, _from, prefix, adapter) do
    process_source(source_schema, fields, row, true, prefix, adapter)
  end
  defp process([value | row], {:value, :any}, _from, _prefix, _adapter) do
    {value, row}
  end
  defp process([value | row], {:value, type}, _from, _prefix, adapter) do
    {load!(type, value, nil, nil, adapter), row}
  end
  defp process(row, value, _from, _prefix, _adapter)
       when is_binary(value) or is_number(value) or is_atom(value) do
    {value, row}
  end

  defp process_update(data, args, row, from, prefix, adapter) do
    {args, row} = process_kv(args, row, from, prefix, adapter)
    data = Enum.reduce(args, data, fn {key, value}, acc -> %{acc | key => value} end)
    {data, row}
  end

  defp process_source({source, schema}, types, row, all_nil?, prefix, adapter) do
    case split_values(types, row, [], all_nil?) do
      {nil, row} ->
        {nil, row}
      {values, row} ->
        struct = if schema, do: schema.__struct__(), else: %{}
        loader = &Ecto.Type.adapter_load(adapter, &1, &2)
        {Ecto.Schema.__safe_load__(struct, types, values, prefix, source, loader), row}
    end
  end

  defp split_values([_ | types], [nil | values], acc, all_nil?) do
    split_values(types, values, [nil | acc], all_nil?)
  end
  defp split_values([_ | types], [value | values], acc, _all_nil?) do
    split_values(types, values, [value | acc], false)
  end
  defp split_values([], values, _acc, true) do
    {nil, values}
  end
  defp split_values([], values, acc, false) do
    {Enum.reverse(acc), values}
  end

  defp process_args(args, row, from, prefix, adapter) do
    Enum.map_reduce(args, row, fn arg, row ->
      process(row, arg, from, prefix, adapter)
    end)
  end

  defp process_kv(kv, row, from, prefix, adapter) do
    Enum.map_reduce(kv, row, fn {key, value}, row ->
      {key, row} = process(row, key, from, prefix, adapter)
      {value, row} = process(row, value, from, prefix, adapter)
      {{key, value}, row}
    end)
  end

  defp load!(type, value, field, struct, adapter) do
    case Ecto.Type.adapter_load(adapter, type, value) do
      {:ok, value} ->
        value
      :error ->
        field = field && " for field #{inspect field}"
        struct = struct && " in #{inspect struct}"
        raise ArgumentError, "cannot load `#{inspect value}` as type #{inspect type}#{field}#{struct}"
    end
  end

  defp to_map(nil, _fields) do
    nil
  end
  defp to_map(value, fields) when is_list(value) do
    Enum.map(value, &to_map(&1, fields))
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
