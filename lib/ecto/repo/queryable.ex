defmodule Ecto.Repo.Queryable do
  @moduledoc false

  alias Ecto.Queryable
  alias Ecto.Query
  alias Ecto.Query.Planner
  alias Ecto.Query.SelectExpr

  require Ecto.Query

  def all(name, queryable, opts) when is_list(opts) do
    query =
      queryable
      |> Ecto.Queryable.to_query()
      |> Ecto.Query.Planner.ensure_select(true)

    execute(:all, name, query, opts) |> elem(1)
  end

  def stream(name, queryable, opts) when is_list(opts) do
    query =
      queryable
      |> Ecto.Queryable.to_query()
      |> Ecto.Query.Planner.ensure_select(true)

    {adapter, %{cache: cache, repo: repo} = adapter_meta} = Ecto.Repo.Registry.lookup(name)
    {query, opts} = repo.prepare_query(:stream, query, opts)
    query = attach_prefix(query, opts)
    {query_meta, prepared, params} = Planner.query(query, :all, cache, adapter, 0)

    case query_meta do
      %{select: nil} ->
        adapter_meta
        |> adapter.stream(query_meta, prepared, params, opts)
        |> Stream.flat_map(fn {_, nil} -> [] end)

      %{select: select, preloads: preloads} ->
        %{
          assocs: assocs,
          preprocess: preprocess,
          postprocess: postprocess,
          take: take,
          from: from
        } = select

        if preloads != [] or assocs != [] do
          raise Ecto.QueryError, query: query, message: "preloads are not supported on streams"
        end

        preprocessor = preprocessor(from, preprocess, adapter)
        stream = adapter.stream(adapter_meta, query_meta, prepared, params, opts)
        postprocessor = postprocessor(from, postprocess, take, adapter)

        stream
        |> Stream.flat_map(fn {_, rows} -> rows end)
        |> Stream.map(preprocessor)
        |> Stream.map(postprocessor)
    end
  end

  def get(name, queryable, id, opts) do
    one(name, query_for_get(queryable, id), opts)
  end

  def get!(name, queryable, id, opts) do
    one!(name, query_for_get(queryable, id), opts)
  end

  def get_by(name, queryable, clauses, opts) do
    one(name, query_for_get_by(queryable, clauses), opts)
  end

  def get_by!(name, queryable, clauses, opts) do
    one!(name, query_for_get_by(queryable, clauses), opts)
  end

  def aggregate(name, queryable, aggregate, opts) do
    one!(name, query_for_aggregate(queryable, aggregate), opts)
  end

  def aggregate(name, queryable, aggregate, field, opts) do
    one!(name, query_for_aggregate(queryable, aggregate, field), opts)
  end

  def exists?(name, queryable, opts) do
    queryable =
      Query.exclude(queryable, :select)
      |> Query.exclude(:preload)
      |> Query.exclude(:order_by)
      |> Query.exclude(:distinct)
      |> Query.select(1)
      |> Query.limit(1)

    case all(name, queryable, opts) do
      [1] -> true
      [] -> false
    end
  end

  def one(name, queryable, opts) do
    case all(name, queryable, opts) do
      [one] -> one
      [] -> nil
      other -> raise Ecto.MultipleResultsError, queryable: queryable, count: length(other)
    end
  end

  def one!(name, queryable, opts) do
    case all(name, queryable, opts) do
      [one] -> one
      [] -> raise Ecto.NoResultsError, queryable: queryable
      other -> raise Ecto.MultipleResultsError, queryable: queryable, count: length(other)
    end
  end

  def update_all(name, queryable, [], opts) when is_list(opts) do
    update_all(name, queryable, opts)
  end

  def update_all(name, queryable, updates, opts) when is_list(opts) do
    query = Query.from(queryable, update: ^updates)
    update_all(name, query, opts)
  end

  defp update_all(name, queryable, opts) do
    query = Ecto.Queryable.to_query(queryable)
    execute(:update_all, name, query, opts)
  end

  def delete_all(name, queryable, opts) when is_list(opts) do
    query = Ecto.Queryable.to_query(queryable)
    execute(:delete_all, name, query, opts)
  end

  @doc """
  Load structs from query.
  """
  def struct_load!([{field, type} | types], [value | values], acc, all_nil?, struct, adapter) do
    all_nil? = all_nil? and value == nil
    value = load!(type, value, field, struct, adapter)
    struct_load!(types, values, [{field, value} | acc], all_nil?, struct, adapter)
  end

  def struct_load!([], values, _acc, true, _struct, _adapter) do
    {nil, values}
  end

  def struct_load!([], values, acc, false, struct, _adapter) do
    {Map.merge(struct, Map.new(acc)), values}
  end

  ## Helpers

  defp attach_prefix(query, opts) do
    case Keyword.fetch(opts, :prefix) do
      {:ok, prefix} -> %{query | prefix: prefix}
      :error -> query
    end
  end

  defp execute(operation, name, query, opts) when is_list(opts) do
    {adapter, %{cache: cache, repo: repo} = adapter_meta} = Ecto.Repo.Registry.lookup(name)
    {query, opts} = repo.prepare_query(operation, query, opts)
    query = attach_prefix(query, opts)
    {query_meta, prepared, params} = Planner.query(query, operation, cache, adapter, 0)

    case query_meta do
      %{select: nil} ->
        adapter.execute(adapter_meta, query_meta, prepared, params, opts)

      %{select: select, sources: sources, preloads: preloads} ->
        %{
          preprocess: preprocess,
          postprocess: postprocess,
          take: take,
          assocs: assocs,
          from: from
        } = select

        preprocessor = preprocessor(from, preprocess, adapter)
        {count, rows} = adapter.execute(adapter_meta, query_meta, prepared, params, opts)
        postprocessor = postprocessor(from, postprocess, take, adapter)

        {count,
         rows
         |> Ecto.Repo.Assoc.query(assocs, sources, preprocessor)
         |> Ecto.Repo.Preloader.query(name, preloads, take, postprocessor, opts)}
    end
  end

  defp preprocessor({_, {:source, {source, schema}, prefix, types}}, preprocess, adapter) do
    struct = Ecto.Schema.Loader.load_struct(schema, prefix, source)

    fn row ->
      {entry, rest} = struct_load!(types, row, [], false, struct, adapter)
      preprocess(rest, preprocess, entry, adapter)
    end
  end

  defp preprocessor({_, from}, preprocess, adapter) do
    fn row ->
      {entry, rest} = process(row, from, nil, adapter)
      preprocess(rest, preprocess, entry, adapter)
    end
  end

  defp preprocessor(:none, preprocess, adapter) do
    fn row ->
      preprocess(row, preprocess, nil, adapter)
    end
  end

  defp preprocess(row, [], _from, _adapter) do
    row
  end

  defp preprocess(row, [source | sources], from, adapter) do
    {entry, rest} = process(row, source, from, adapter)
    [entry | preprocess(rest, sources, from, adapter)]
  end

  defp postprocessor({:any, _}, postprocess, _take, adapter) do
    fn [from | row] ->
      row |> process(postprocess, from, adapter) |> elem(0)
    end
  end

  defp postprocessor({:map, _}, postprocess, take, adapter) do
    fn [from | row] ->
      row |> process(postprocess, to_map(from, take), adapter) |> elem(0)
    end
  end

  defp postprocessor(:none, postprocess, _take, adapter) do
    fn row -> row |> process(postprocess, nil, adapter) |> elem(0) end
  end

  defp process(row, {:source, :from}, from, _adapter) do
    {from, row}
  end

  defp process(row, {:source, {source, schema}, prefix, types}, _from, adapter) do
    struct = Ecto.Schema.Loader.load_struct(schema, prefix, source)
    struct_load!(types, row, [], true, struct, adapter)
  end

  defp process(row, {:merge, left, right}, from, adapter) do
    {left, row} = process(row, left, from, adapter)
    {right, row} = process(row, right, from, adapter)

    data =
      case {left, right} do
        {%{__struct__: s}, %{__struct__: s}} ->
          Map.merge(left, right)

        {%{__struct__: left_struct}, %{__struct__: right_struct}} ->
          raise ArgumentError,
                "cannot merge structs of different types, " <>
                  "got: #{inspect(left_struct)} and #{inspect(right_struct)}"

        {%{__struct__: name}, %{}} ->
          for {key, _} <- right, not Map.has_key?(left, key) do
            raise ArgumentError, "struct #{inspect(name)} does not have the key #{inspect(key)}"
          end

          Map.merge(left, right)

        {%{}, %{}} ->
          Map.merge(left, right)

        {_, %{}} ->
          raise ArgumentError,
                "cannot merge because the left side is not a map, got: #{inspect(left)}"

        {%{}, _} ->
          raise ArgumentError,
                "cannot merge because the right side is not a map, got: #{inspect(right)}"
      end

    {data, row}
  end

  defp process(row, {:struct, struct, data, args}, from, adapter) do
    case process(row, data, from, adapter) do
      {%{__struct__: ^struct} = data, row} ->
        process_update(data, args, row, from, adapter)

      {data, _row} ->
        raise BadStructError, struct: struct, term: data
    end
  end

  defp process(row, {:struct, struct, args}, from, adapter) do
    {fields, row} = process_kv(args, row, from, adapter)

    case Map.merge(struct.__struct__(), Map.new(fields)) do
      %{__meta__: %Ecto.Schema.Metadata{state: state} = metadata} = struct
      when state != :loaded ->
        {Map.put(struct, :__meta__, %{metadata | state: :loaded}), row}

      map ->
        {map, row}
    end
  end

  defp process(row, {:map, data, args}, from, adapter) do
    {data, row} = process(row, data, from, adapter)
    process_update(data, args, row, from, adapter)
  end

  defp process(row, {:map, args}, from, adapter) do
    {args, row} = process_kv(args, row, from, adapter)
    {Map.new(args), row}
  end

  defp process(row, {:list, args}, from, adapter) do
    process_args(args, row, from, adapter)
  end

  defp process(row, {:tuple, args}, from, adapter) do
    {args, row} = process_args(args, row, from, adapter)
    {List.to_tuple(args), row}
  end

  defp process([value | row], {:value, :any}, _from, _adapter) do
    {value, row}
  end

  defp process([value | row], {:value, type}, _from, adapter) do
    {load!(type, value, nil, nil, adapter), row}
  end

  defp process(row, value, _from, _adapter)
       when is_binary(value) or is_number(value) or is_atom(value) do
    {value, row}
  end

  defp process_update(data, args, row, from, adapter) do
    {args, row} = process_kv(args, row, from, adapter)
    data = Enum.reduce(args, data, fn {key, value}, acc -> %{acc | key => value} end)
    {data, row}
  end

  defp process_args(args, row, from, adapter) do
    Enum.map_reduce(args, row, fn arg, row ->
      process(row, arg, from, adapter)
    end)
  end

  defp process_kv(kv, row, from, adapter) do
    Enum.map_reduce(kv, row, fn {key, value}, row ->
      {key, row} = process(row, key, from, adapter)
      {value, row} = process(row, value, from, adapter)
      {{key, value}, row}
    end)
  end

  @compile {:inline, load!: 5}
  defp load!(type, value, field, struct, adapter) do
    case Ecto.Type.adapter_load(adapter, type, value) do
      {:ok, value} ->
        value

      :error ->
        field = field && " for field #{inspect(field)}"
        struct = struct && " in #{inspect(struct)}"

        raise ArgumentError,
              "cannot load `#{inspect(value)}` as type #{inspect(type)}#{field}#{struct}"
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

  defp query_for_get(_queryable, nil) do
    raise ArgumentError, "cannot perform Ecto.Repo.get/2 because the given value is nil"
  end

  defp query_for_get(queryable, id) do
    query = Queryable.to_query(queryable)
    schema = assert_schema!(query)

    case schema.__schema__(:primary_key) do
      [pk] ->
        Query.from(x in query, where: field(x, ^pk) == ^id)

      pks ->
        raise ArgumentError,
              "Ecto.Repo.get/2 requires the schema #{inspect(schema)} " <>
                "to have exactly one primary key, got: #{inspect(pks)}"
    end
  end

  defp query_for_get_by(queryable, clauses) do
    Query.where(queryable, [], ^Enum.to_list(clauses))
  end

  defp query_for_aggregate(queryable, aggregate) do
    query =
      case prepare_for_aggregate(queryable) do
        %{distinct: nil, limit: nil, offset: nil} = query ->
          %{query | order_bys: []}

        query ->
          query
          |> Query.subquery()
          |> Queryable.Ecto.SubQuery.to_query()
      end

    select = %SelectExpr{expr: {aggregate, [], []}, file: __ENV__.file, line: __ENV__.line}
    %{query | select: select}
  end

  defp query_for_aggregate(queryable, aggregate, field) do
    ast = field(0, field)

    query =
      case prepare_for_aggregate(queryable) do
        %{distinct: nil, limit: nil, offset: nil} = query ->
          %{query | order_bys: []}

        query ->
          select = %SelectExpr{expr: ast, file: __ENV__.file, line: __ENV__.line}

          %{query | select: select}
          |> Query.subquery()
          |> Queryable.Ecto.SubQuery.to_query()
      end

    select = %SelectExpr{expr: {aggregate, [], [ast]}, file: __ENV__.file, line: __ENV__.line}
    %{query | select: select}
  end

  defp prepare_for_aggregate(queryable) do
    case %{Queryable.to_query(queryable) | preloads: [], assocs: []} do
      %{group_bys: [_ | _]} = query ->
        raise Ecto.QueryError, message: "cannot aggregate on query with group_by", query: query

      %{} = query ->
        query
    end
  end

  defp field(ix, field) when is_integer(ix) and is_atom(field) do
    {{:., [], [{:&, [], [ix]}, field]}, [], []}
  end

  defp assert_schema!(%{from: %{source: {_source, schema}}}) when schema != nil, do: schema

  defp assert_schema!(query) do
    raise Ecto.QueryError,
      query: query,
      message: "expected a from expression with a schema"
  end
end
