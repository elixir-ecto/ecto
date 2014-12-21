defmodule Ecto.Query.Planner do
  # Normalizes a query and its parameters.
  @moduledoc false

  alias Ecto.Query.QueryExpr
  alias Ecto.Query.JoinExpr

  @doc """
  Plans the query for execution.

  Planning happens in multiple steps:

    1. First the query is prepared by retreiving
       its cache key, casting and merging parameters

    2. Then a cache lookup is done, if the query is
       cached, we are done

    3. If there is no cache, we need to actually
       normalize and validate the query, before sending
       it to the adapter

    4. The query is sent to the adapter to be generated

  Currently only steps 1 and 3 are implemented.
  """
  def plan(query, base, opts \\ []) do
    {query, params} = prepare(query, base)
    {normalize(query, base, opts), params}
  end

  @doc """
  Prepares the query for cache.

  This means all the parameters from query expressions are
  merged into a single value and their entries are prunned
  from the query.

  In the future, this function should also calculate a hash
  to be used as cache key.

  This function is called by the backend before invoking
  any cache mechanism.
  """
  def prepare(query, params) do
    query
    |> prepare_sources
    |> traverse_query(params, &merge_params/4)
  end

  defp merge_params(kind, _query, expr, params) when kind in ~w(from lock)a do
    {expr, params}
  end

  defp merge_params(kind, query, expr, params) when kind in ~w(select limit offset)a do
    if expr do
      {put_in(expr.params, nil),
       cast_and_merge_params(query, params, expr.params)}
   else
      {expr, params}
    end
  end

  defp merge_params(kind, query, exprs, params) when kind in ~w(distinct where group_by having order_by)a do
    Enum.map_reduce exprs, params, fn expr, acc ->
      {put_in(expr.params, nil),
       cast_and_merge_params(query, acc, expr.params)}
    end
  end

  defp merge_params(:join, query, exprs, params) do
    Enum.map_reduce exprs, params, fn join, acc ->
      {put_in(join.on.params, nil),
       cast_and_merge_params(query, acc, join.on.params)}
    end
  end

  # TODO: Add cast
  # TODO: Add type validation
  defp cast_and_merge_params(_query, params, expr_params) do
    size = Map.size(params)
    Enum.reduce expr_params, params, fn {k, {v, _}}, acc ->
      Map.put acc, k + size, v
    end
  end

  # Normalize all sources and adds a source
  # field to the query for fast access.
  defp prepare_sources(query) do
    from = query.from || error!("query must have a from expression")

    {joins, sources} =
      Enum.map_reduce(query.joins, [from], &prepare_join(&1, &2, query))

    %{query | sources: sources |> Enum.reverse |> List.to_tuple, joins: joins}
  end

  defp prepare_join(%JoinExpr{assoc: {ix, assoc}} = join, sources, query) do
    {_, model} = Enum.fetch!(Enum.reverse(sources), ix)

    unless model do
      error! query, join, "association join cannot be performed without a model"
    end

    refl = model.__schema__(:association, assoc)

    unless refl do
      error! query, join, "could not find association `#{assoc}` on model #{inspect model}"
    end

    associated = refl.associated
    source     = {associated.__schema__(:source), associated}

    on = on_expr(join.on, refl, ix, length(sources))
    {%{join | source: source, on: on}, [source|sources]}
  end

  defp prepare_join(%JoinExpr{source: {source, nil}} = join, sources, _query) when is_binary(source) do
    source = {source, nil}
    {%{join | source: source}, [source|sources]}
  end

  defp prepare_join(%JoinExpr{source: {nil, model}} = join, sources, _query) when is_atom(model) do
    source = {model.__schema__(:source), model}
    {%{join | source: source}, [source|sources]}
  end

  defp on_expr(on, refl, var_ix, assoc_ix) do
    key = refl.key
    var = {:&, [], [var_ix]}
    assoc_key = refl.assoc_key
    assoc_var = {:&, [], [assoc_ix]}

    expr = quote do
      unquote(assoc_var).unquote(assoc_key) == unquote(var).unquote(key)
    end

    case on.expr do
      true -> %{on | expr: expr}
      _    -> %{on | expr: quote do: unquote(on.expr) and unquote(expr)}
    end
  end

  @doc """
  Normalizes the query.

  After the query was prepared and there is no cache
  entry, we need to update its interpolations and check
  its fields and associations exist and are valid.
  """
  def normalize(query, base, opts) do
    query
    |> traverse_query(map_size(base), &increment_params/4)
    |> elem(0)
    |> auto_select(opts)
  end

  defp increment_params(kind, _query, expr, counter) when kind in ~w(from lock)a do
    {expr, counter}
  end

  defp increment_params(kind, _query, expr, counter) when kind in ~w(select limit offset)a do
    if expr do
      increment_params expr, counter
    else
      {nil, counter}
    end
  end

  defp increment_params(kind, _query, exprs, counter) when kind in ~w(distinct where group_by having order_by)a do
    Enum.map_reduce exprs, counter, &increment_params/2
  end

  defp increment_params(:join, _query, exprs, counter) do
    Enum.map_reduce exprs, counter, fn join, acc ->
      {on, acc} = increment_params join.on, acc
      {%{join | on: on}, acc}
    end
  end

  defp increment_params(expr, counter) do
    {inner, acc} = Macro.prewalk expr.expr, counter, fn
      {:^, meta, [idx]}, acc ->
        {{:^, meta, [idx + counter]}, acc + 1}
      other, acc ->
        {other, acc}
    end
    {%{expr | expr: inner}, acc}
  end

  # Auto select the model in the from expression
  defp auto_select(query, opts) do
    if !opts[:skip_select] && query.select == nil do
      var = {:&, [], [0]}
      %{query | select: %QueryExpr{expr: var}}
    else
      query
    end
  end

  ## Helpers

  defp traverse_query(original, acc, fun) do
    query = original

    {select, acc} = fun.(:select, original, original.select, acc)
    query = %{query | select: select}

    {distincts, acc} = fun.(:distinct, original, original.distincts, acc)
    query = %{query | distincts: distincts}

    {from, acc} = fun.(:from, original, original.from, acc)
    query = %{query | from: from}

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
    query = %{query | offset: offset}

    {lock, acc} = fun.(:lock, original, original.lock, acc)
    {%{query | lock: lock}, acc}
  end

  defp error!(message) do
    raise Ecto.QueryError, message: message
  end

  defp error!(query, expr, message) do
    raise Ecto.QueryError, message: message, query: query, file: expr.file, line: expr.line
  end
end
