defmodule Ecto.Repo.Queryable do
  # The module invoked by user defined repos
  # for query related functionality.
  @moduledoc false

  alias Ecto.Queryable
  alias Ecto.Query.Planner

  require Ecto.Query

  def all(repo, adapter, queryable, opts) when is_list(opts) do
    execute(:all, repo, adapter, queryable, opts) |> elem(1)
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

  def first(repo, adapter, queryable, opts) do
    one(repo, adapter, query_for_first(repo, queryable), opts)
  end

  def first!(repo, adapter, queryable, opts) do
    one!(repo, adapter, query_for_first(repo, queryable), opts)
  end

  def last(repo, adapter, queryable, opts) do
    one(repo, adapter, query_for_last(repo, queryable), opts)
  end

  def last!(repo, adapter, queryable, opts) do
    one!(repo, adapter, query_for_last(repo, queryable), opts)
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
    query = Ecto.Query.from q in queryable, update: ^updates
    update_all(repo, adapter, query, opts)
  end

  defp update_all(repo, adapter, queryable, opts) do
    execute(:update_all, repo, adapter, queryable, opts)
  end

  def delete_all(repo, adapter, queryable, opts) when is_list(opts) do
    execute(:delete_all, repo, adapter, queryable, opts)
  end

  ## Helpers

  def execute(operation, repo, adapter, queryable, opts) when is_list(opts) do
    {meta, prepared, params} =
      queryable
      |> Queryable.to_query()
      |> Planner.query(operation, repo, adapter)

    case meta do
      %{select: nil} ->
        adapter.execute(repo, meta, prepared, params, nil, opts)
      %{select: select, prefix: prefix, sources: sources, assocs: assocs, preloads: preloads} ->
        preprocess = preprocess(prefix, sources, adapter)
        {count, rows} = adapter.execute(repo, meta, prepared, params, preprocess, opts)
        {count,
          rows
          |> Ecto.Repo.Assoc.query(assocs, sources)
          |> Ecto.Repo.Preloader.query(repo, preloads, assocs, postprocess(select), opts)}
    end
  end

  defp preprocess(prefix, sources, adapter) do
    &preprocess(&1, &2, prefix, &3, sources, adapter)
  end

  defp preprocess({:&, _, [ix, fields]}, value, prefix, context, sources, adapter) do
    case elem(sources, ix) do
      {_source, nil} when is_map(value) ->
        value
      {_source, nil} when is_list(value) ->
        load_schemaless(fields, value, %{})
      {source, schema} ->
        Ecto.Schema.__load__(schema, prefix, source, context, {fields, value},
                             &Ecto.Type.adapter_load(adapter, &1, &2))
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

  defp preprocess(%Ecto.Query.Tagged{tag: tag}, value, _prefix, _context, _sources, adapter) do
    load!(tag, value, adapter)
  end

  defp preprocess(_key, value, _prefix, _context, _sources, _adapter) do
    value
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

  defp postprocess(%{expr: expr, fields: fields}) do
    # The planner always put the from as the first
    # entry in the query, avoiding fetching it multiple
    # times even if it appears multiple times in the query.
    # So we always need to handle it specially.
    from? = match?([{:&, _, [0, _]}|_], fields)
    &postprocess(&1, expr, from?)
  end

  defp postprocess(row, expr, true),
    do: transform_row(expr, hd(row), tl(row)) |> elem(0)
  defp postprocess(row, expr, false),
    do: transform_row(expr, nil, row) |> elem(0)

  defp transform_row({:&, _, [0]}, from, values) do
    {from, values}
  end

  defp transform_row({:{}, _, list}, from, values) do
    {result, values} = transform_row(list, from, values)
    {List.to_tuple(result), values}
  end

  defp transform_row({left, right}, from, values) do
    {[left, right], values} = transform_row([left, right], from, values)
    {{left, right}, values}
  end

  defp transform_row({:%{}, _, pairs}, from, values) do
    Enum.reduce pairs, {%{}, values}, fn {k, v}, {map, acc} ->
      {k, acc} = transform_row(k, from, acc)
      {v, acc} = transform_row(v, from, acc)
      {Map.put(map, k, v), acc}
    end
  end

  defp transform_row(list, from, values) when is_list(list) do
    Enum.map_reduce(list, values, &transform_row(&1, from, &2))
  end

  defp transform_row(expr, _from, values) when is_atom(expr) or is_binary(expr) or is_number(expr) do
    {expr, values}
  end

  defp transform_row(_, _from, values) do
    [value|values] = values
    {value, values}
  end

  defp query_for_get(repo, _queryable, nil) do
    raise ArgumentError, "cannot perform #{inspect repo}.get/2 because the given value is nil"
  end

  defp query_for_get(repo, queryable, id) do
    query = Queryable.to_query(queryable)
    Ecto.Query.from(x in query, where: field(x, ^assert_pk!(repo, query)) == ^id)
  end

  defp query_for_get_by(_repo, queryable, clauses) do
    Ecto.Query.where(queryable, [], ^Enum.to_list(clauses))
  end

  defp query_for_first(repo, queryable) do
    query = %{Queryable.to_query(queryable) | limit: limit()}
    case query do
      %{order_bys: []} ->
        %{query | order_bys: [order_by_pk(repo, query, :asc)]}
      %{} ->
        query
    end
  end

  defp query_for_last(repo, queryable) do
    query = %{Queryable.to_query(queryable) | limit: limit()}
    update_in query.order_bys, fn
      [] ->
        [order_by_pk(repo, query, :desc)]
      order_bys ->
        for %{expr: expr} = order_by <- order_bys do
          %{order_by | expr:
              Enum.map(expr, fn
                {:desc, ast} -> {:asc, ast}
                {:asc, ast} -> {:desc, ast}
              end)}
        end
    end
  end

  defp limit do
    %Ecto.Query.QueryExpr{expr: 1, params: [], file: __ENV__.file, line: __ENV__.line}
  end

  defp order_by_pk(repo, query, dir) do
    %Ecto.Query.QueryExpr{expr: [{dir, {{:., [], [{:&, [], [0]}, assert_pk!(repo, query)]}, [], []}}],
                          params: [], file: __ENV__.file, line: __ENV__.line}
  end

  defp assert_pk!(repo, query) do
    schema = assert_schema!(query)
    case schema.__schema__(:primary_key) do
      [pk] -> pk
      pks ->
        raise ArgumentError,
          "#{inspect repo}.get/2 requires the schema #{inspect schema} " <>
          "to have exactly one primary key, got: #{inspect pks}"
    end
  end

  defp assert_schema!(%{from: {_source, schema}}) when schema != nil, do: schema
  defp assert_schema!(query) do
    raise Ecto.QueryError,
      query: query,
      message: "expected a from expression with a schema"
  end
end
