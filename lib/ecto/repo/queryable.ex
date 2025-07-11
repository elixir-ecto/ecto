defmodule Ecto.Repo.Queryable do
  @moduledoc false

  alias Ecto.Queryable
  alias Ecto.Query
  alias Ecto.Query.Planner
  alias Ecto.Query.SelectExpr

  import Ecto.Query.Planner, only: [attach_prefix: 2]

  require Ecto.Query

  def all(name, queryable, tuplet) do
    query =
      queryable
      |> Ecto.Queryable.to_query()
      |> Ecto.Query.Planner.ensure_select(true)

    execute(:all, name, query, tuplet) |> elem(1)
  end

  def all_by(name, queryable, clauses, tuplet) do
    query =
      queryable
      |> Ecto.Query.where([], ^Enum.to_list(clauses))
      |> Ecto.Query.Planner.ensure_select(true)

    execute(:all, name, query, tuplet) |> elem(1)
  end

  def stream(_name, queryable, {adapter_meta, opts}) do
    %{adapter: adapter, cache: cache, repo: repo} = adapter_meta

    query =
      queryable
      |> Ecto.Queryable.to_query()
      |> Ecto.Query.Planner.ensure_select(true)

    {query, opts} = repo.prepare_query(:stream, query, opts)
    query = attach_prefix(query, opts)

    {query_meta, prepared, cast_params, dump_params} =
      Planner.query(query, :all, cache, adapter, 0)

    opts = [cast_params: cast_params] ++ opts

    case query_meta do
      %{select: nil} ->
        adapter_meta
        |> adapter.stream(query_meta, prepared, dump_params, opts)
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
        stream = adapter.stream(adapter_meta, query_meta, prepared, dump_params, opts)
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

  def reload(name, [head | _] = structs, opts) when is_list(structs) do
    results = all(name, query_for_reload(structs), opts)

    [pk] = head.__struct__.__schema__(:primary_key)

    for struct <- structs do
      struct_pk = Map.fetch!(struct, pk)
      Enum.find(results, &(Map.fetch!(&1, pk) == struct_pk))
    end
  end

  def reload(name, struct, opts) do
    one(name, query_for_reload([struct]), opts)
  end

  def reload!(name, [head | _] = structs, opts) when is_list(structs) do
    query = query_for_reload(structs)
    results = all(name, query, opts)

    [pk] = head.__struct__.__schema__(:primary_key)

    for struct <- structs do
      struct_pk = Map.fetch!(struct, pk)

      Enum.find(results, &(Map.fetch!(&1, pk) == struct_pk)) ||
        raise "could not reload #{inspect(struct)}, maybe it doesn't exist or was deleted"
    end
  end

  def reload!(name, struct, opts) do
    query = query_for_reload([struct])
    one!(name, query, opts)
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
      |> rewrite_combinations()

    case all(name, queryable, opts) do
      [1] -> true
      [] -> false
    end
  end

  defp rewrite_combinations(%{combinations: []} = query), do: query

  defp rewrite_combinations(%{combinations: combinations} = query) do
    combinations =
      Enum.map(combinations, fn {type, query} ->
        {type, query |> Query.exclude(:select) |> Query.select(1)}
      end)

    %{query | combinations: combinations}
  end

  def one(name, queryable, tuplet) do
    case all(name, queryable, tuplet) do
      [one] -> one
      [] -> nil
      other -> raise Ecto.MultipleResultsError, queryable: queryable, count: length(other)
    end
  end

  def one!(name, queryable, tuplet) do
    case all(name, queryable, tuplet) do
      [one] -> one
      [] -> raise Ecto.NoResultsError, queryable: queryable
      other -> raise Ecto.MultipleResultsError, queryable: queryable, count: length(other)
    end
  end

  def update_all(name, queryable, [], tuplet) do
    update_all(name, queryable, tuplet)
  end

  def update_all(name, queryable, updates, tuplet) do
    query = Query.from(queryable, update: ^updates)
    update_all(name, query, tuplet)
  end

  defp update_all(name, queryable, tuplet) do
    query = Ecto.Queryable.to_query(queryable)
    execute(:update_all, name, query, tuplet)
  end

  def delete_all(name, queryable, tuplet) do
    query = Ecto.Queryable.to_query(queryable)
    execute(:delete_all, name, query, tuplet)
  end

  @doc """
  Load structs from query.
  """
  def struct_load!([{field, type} | types], [value | values], acc, all_nil?, struct, adapter) do
    all_nil? = all_nil? and value == nil
    value = load!(type, value, field, struct, adapter)
    struct_load!(types, values, [{field, value} | acc], all_nil?, struct, adapter)
  end

  def struct_load!([], values, _acc, true, struct, _adapter) when struct != %{} do
    {nil, values}
  end

  def struct_load!([], values, acc, _all_nil?, struct, _adapter) do
    {Map.merge(struct, Map.new(acc)), values}
  end

  ## Helpers

  defp execute(operation, name, query, {adapter_meta, opts} = tuplet) do
    %{adapter: adapter, cache: cache, repo: repo} = adapter_meta

    {query, opts} = repo.prepare_query(operation, query, opts)
    query = attach_prefix(query, opts)

    {query_meta, prepared, cast_params, dump_params} =
      Planner.query(query, operation, cache, adapter, 0)

    opts = [cast_params: cast_params] ++ opts

    case query_meta do
      %{select: nil} ->
        adapter.execute(adapter_meta, query_meta, prepared, dump_params, opts)

      %{select: select, sources: sources, preloads: preloads} ->
        %{
          preprocess: preprocess,
          postprocess: postprocess,
          take: take,
          assocs: assocs,
          from: from
        } = select

        preprocessor = preprocessor(from, preprocess, adapter)
        {count, rows} = adapter.execute(adapter_meta, query_meta, prepared, dump_params, opts)
        postprocessor = postprocessor(from, postprocess, take, adapter)

        {count,
         rows
         |> Ecto.Repo.Assoc.query(assocs, sources, preprocessor)
         |> Ecto.Repo.Preloader.query(name, preloads, take, assocs, postprocessor, tuplet)}
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

  defp process(row, {:source, :values, _prefix, types}, _from, adapter) do
    values_list_load!(types, row, [], true, adapter)
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

        {%{}, nil} ->
          left

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
        raise ArgumentError,
              "expected a struct named #{inspect(struct)}, got: #{inspect(data)}"
    end
  end

  defp process(row, {:struct, struct, args}, from, adapter) do
    {fields, row} = process_kv(args, row, from, adapter)

    case Map.merge(struct.__struct__(), Map.new(fields)) do
      %{__meta__: %Ecto.Schema.Metadata{state: state} = metadata} = struct
      when state != :loaded ->
        {Map.replace!(struct, :__meta__, %{metadata | state: :loaded}), row}

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

  defp process_update(nil, args, row, from, adapter) do
    {_args, row} = process_kv(args, row, from, adapter)
    {nil, row}
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
              "cannot load `#{inspect(value)}` as type #{Ecto.Type.format(type)}#{field}#{struct}"
    end
  end

  defp values_list_load!([{field, type} | types], [value | values], acc, all_nil?, adapter) do
    all_nil? = all_nil? and value == nil
    value = load!(type, value, field, nil, adapter)
    values_list_load!(types, values, [{field, value} | acc], all_nil?, adapter)
  end

  defp values_list_load!([], values, _acc, true, _adapter) do
    {nil, values}
  end

  defp values_list_load!([], values, acc, false, _adapter) do
    {Map.new(acc), values}
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

  defp query_for_reload([head | _] = structs) do
    assert_structs!(structs)

    schema = head.__struct__
    %{prefix: prefix, source: source} = head.__meta__

    case schema.__schema__(:primary_key) do
      [pk] ->
        keys = Enum.map(structs, &get_pk!(&1, pk))
        query = Query.from(x in {source, schema}, where: field(x, ^pk) in ^keys)
        %{query | prefix: prefix}

      pks ->
        raise ArgumentError,
              "Ecto.Repo.reload/2 requires the schema #{inspect(schema)} " <>
                "to have exactly one primary key, got: #{inspect(pks)}"
    end
  end

  defp query_for_aggregate(queryable, aggregate) do
    query =
      case prepare_for_aggregate(queryable) do
        %{distinct: nil, limit: nil, offset: nil, combinations: []} = query ->
          %{query | order_bys: []}

        %{prefix: prefix} = query ->
          query =
            query
            |> Query.subquery()
            |> Queryable.Ecto.SubQuery.to_query()

          %{query | prefix: prefix}
      end

    select = %SelectExpr{expr: {aggregate, [], []}, file: __ENV__.file, line: __ENV__.line}
    %{query | select: select}
  end

  defp query_for_aggregate(queryable, aggregate, field) do
    ast = field(0, field)

    query =
      case prepare_for_aggregate(queryable) do
        %{distinct: nil, limit: nil, offset: nil, combinations: []} = query ->
          %{query | order_bys: []}

        %{prefix: prefix} = query ->
          select = %SelectExpr{expr: ast, file: __ENV__.file, line: __ENV__.line}

          query =
            %{query | select: select}
            |> Query.subquery()
            |> Queryable.Ecto.SubQuery.to_query()

          %{query | prefix: prefix}
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

  defp assert_structs!([head | _] = structs) when is_list(structs) do
    unless Enum.all?(structs, &schema?/1) do
      raise ArgumentError, "expected a struct or a list of structs, received #{inspect(structs)}"
    end

    unless Enum.all?(structs, &(&1.__struct__ == head.__struct__)) do
      raise ArgumentError, "expected an homogeneous list, received different struct types"
    end

    :ok
  end

  defp schema?(%{__meta__: _}), do: true
  defp schema?(_), do: false

  defp get_pk!(struct, pk) do
    struct
    |> Map.fetch!(pk)
    |> case do
      nil ->
        raise ArgumentError,
              "Ecto.Repo.reload/2 expects existent structs, found a `nil` primary key"

      key ->
        key
    end
  end
end
