defmodule Ecto.Query.Planner do
  # Normalizes a query and its parameters.
  @moduledoc false

  alias Ecto.Query.QueryExpr
  alias Ecto.Query.JoinExpr
  alias Ecto.Query.Util
  alias Ecto.Query.Types
  alias Ecto.Associations.Assoc

  @doc """
  Plans the struct for query execution.

  This function simply invokes `model/3` passing the persisted
  field names as arguments.
  """
  def struct(kind, %{__struct__: model} = struct) do
    model(kind, model, Map.take(struct, model.__schema__(:fields)))
  end

  @doc """
  Plans the given fields belong to a model for query execution.

  It is mostly a matter of casing the field values.
  """
  def model(kind, model, kw, dumper \\ &Types.dump/2) do
    for {field, value} <- kw do
      type = model.__schema__(:field, field)

      unless type do
        raise Ecto.InvalidModelError,
          message: "field `#{inspect model}.#{field}` in `#{kind}` does not exist in the model source"
      end

      case dumper.(type, value) do
        {:ok, value} ->
          {field, value}
        :error ->
          raise Ecto.InvalidModelError,
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
  """
  def query(query, base, opts \\ []) do
    {query, params} = prepare(query, base)
    {normalize(query, base, opts), params}
  rescue
    e ->
      # Reraise errors so we ignore the planner inner stacktrace
      raise e
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
    |> traverse_exprs(params, &merge_params/4)
  end

  defp merge_params(kind, query, expr, params) when kind in ~w(select limit offset)a do
    if expr do
      {put_in(expr.params, nil),
       cast_and_merge_params(kind, query, expr, params)}
   else
      {expr, params}
    end
  end

  defp merge_params(kind, query, exprs, params) when kind in ~w(distinct where group_by having order_by)a do
    Enum.map_reduce exprs, params, fn expr, acc ->
      {put_in(expr.params, nil),
       cast_and_merge_params(kind, query, expr, acc)}
    end
  end

  defp merge_params(:join, query, exprs, params) do
    Enum.map_reduce exprs, params, fn join, acc ->
      {put_in(join.on.params, nil),
       cast_and_merge_params(:join, query, join.on, acc)}
    end
  end

  defp cast_and_merge_params(kind, query, expr, params) do
    size = Map.size(params)
    Enum.reduce expr.params, params, fn {k, {v, type}}, acc ->
      Map.put acc, k + size, cast_param(kind, query, expr, v, type)
    end
  end

  defp cast_param(kind, query, expr, v, {composite, {idx, field}}) when is_integer(idx) do
    {_, model} = elem(query.sources, idx)
    type = type!(kind, query, expr, model, field)
    cast_param(kind, query, expr, model, field, v, {composite, type})
  end

  defp cast_param(kind, query, expr, v, {idx, field}) when is_integer(idx) do
    {_, model} = elem(query.sources, idx)
    type = type!(kind, query, expr, model, field)
    cast_param(kind, query, expr, model, field, v, type)
  end

  defp cast_param(kind, query, expr, v, type) do
    case Types.cast(type, v) do
      {:ok, nil} ->
        error! query, expr, "value `nil` in `#{kind}` cannot be cast to type #{inspect type} " <>
                            "(if you want to check for nils, use is_nil/1 instead)"
      {:ok, v} ->
        v
      :error ->
        error! query, expr, "value `#{inspect v}` in `#{kind}` cannot be cast to type #{inspect type}"
    end
  end

  defp cast_param(kind, query, expr, model, field, value, type) do
    cast_param(kind, query, expr, value, type)
  rescue
    e in [Ecto.QueryError] ->
      raise Ecto.CastError, model: model, field: field, value: value, type: type,
                            message: Exception.message(e) <>
                                     "\nError when casting value to `#{inspect model}.#{field}`"
  end

  # Normalize all sources and adds a source
  # field to the query for fast access.
  defp prepare_sources(query) do
    from = query.from || error!(query, "query must have a from expression")

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
    only_where? = Keyword.get(opts, :only_where, false)

    query
    |> traverse_exprs(map_size(base), &validate_and_increment/4)
    |> elem(0)
    |> normalize_select(only_where?)
    |> only_where(only_where?)
  end

  defp validate_and_increment(kind, query, expr, counter) when kind in ~w(select limit offset)a do
    if expr do
      do_validate_and_increment(kind, query, expr, counter)
    else
      {nil, counter}
    end
  end

  defp validate_and_increment(kind, query, exprs, counter) when kind in ~w(distinct where group_by having order_by)a do
    Enum.map_reduce exprs, counter, &do_validate_and_increment(kind, query, &1, &2)
  end

  defp validate_and_increment(:join, query, exprs, counter) do
    Enum.map_reduce exprs, counter, fn join, acc ->
      {on, acc} = do_validate_and_increment(:join, query, join.on, acc)
      {%{join | on: on}, acc}
    end
  end

  defp do_validate_and_increment(kind, query, expr, counter) do
    {inner, acc} = Macro.prewalk expr.expr, counter, fn
      {:^, meta, [param]}, acc ->
        {{:^, meta, [param + counter]}, acc + 1}
      {{:., _, [{:&, _, [source]}, field]}, meta, []} = quoted, acc ->
        validate_field(kind, query, expr, source, field, meta)
        {quoted, acc}
      other, acc ->
        {other, acc}
    end
    {%{expr | expr: inner}, acc}
  end

  defp validate_field(kind, query, expr, source, field, meta) do
    {_, model} = elem(query.sources, source)

    if model do
      type = type!(kind, query, expr, model, field)

      if (expected = meta[:ecto_type]) && !Types.match?(type, expected) do
        error! query, expr, "field `#{inspect model}.#{field}` in `#{kind}` does not type check. " <>
                            "It has type #{inspect type} but a type #{inspect expected} is expected"
      end
    end
  end

  # Normalize the select field.
  defp normalize_select(query, only_where?) do
    cond do
      only_where? ->
        query
      query.select ->
        Macro.prewalk(query.select.expr, &validate_select(&1, query))
        query
      true ->
        %{query | select: %QueryExpr{expr: {:&, [], [0]}}}
    end
  end

  defp validate_select({:assoc, _, [var, fields]}, query) do
    validate_assoc(var, fields, query)
  end

  defp validate_select(other, _query) do
    other
  end

  defp validate_assoc(parent_var, fields, query) do
    Enum.each(fields, fn {field, nested} ->
      {_, parent_model} = Util.find_source(query.sources, parent_var)
      refl = parent_model.__schema__(:association, field)

      unless refl do
        error! query, query.select, "field `#{inspect parent_model}.#{field}` " <>
                                    "in assoc/2 is not an association"
      end

      {child_var, child_fields} = Assoc.decompose_assoc(nested)
      {_, child_model} = Util.find_source(query.sources, child_var)

      unless refl.associated == child_model do
        error! query, query.select, "association `#{inspect parent_model}.#{field}` " <>
                                    "in assoc/2 doesn't match join model `#{child_model}`"
      end

      case find_source_expr(query, child_var) do
        %JoinExpr{qual: qual} when qual in [:inner, :left] ->
          :ok
        %JoinExpr{qual: qual} ->
          error! query, query.select, "association `#{inspect parent_model}.#{field}` " <>
                                      "in assoc/2 requires an inner or left join, got #{qual} join"
        _ ->
          :ok
      end

      validate_assoc(child_var, child_fields, query)
    end)
  end

  defp find_source_expr(query, {:&, _, [0]}) do
    query.from
  end

  defp find_source_expr(query, {:&, _, [ix]}) do
    Enum.fetch! query.joins, ix - 1
  end

  if map_size(%Ecto.Query{}) != 14 do
    raise "Ecto.Query match out of date in planner"
  end

  defp only_where(query, false), do: query
  defp only_where(query, true) do
    case query do
      %Ecto.Query{joins: [], select: nil, order_bys: [], limit: nil, offset: nil,
                  group_bys: [], havings: [], preloads: [], distincts: [], lock: nil} ->
        query
      _ ->
        error! query, "only `where` expressions are allowed"
    end
  end

  ## Helpers

  # Traverse all query components with expressions.
  # Therefore from, preload and lock are not traversed.
  defp traverse_exprs(original, acc, fun) do
    query = original

    {select, acc} = fun.(:select, original, original.select, acc)
    query = %{query | select: select}

    {distincts, acc} = fun.(:distinct, original, original.distincts, acc)
    query = %{query | distincts: distincts}

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
      error! query, expr, "field `#{inspect model}.#{field}` in `#{kind}` does not exist in the model source"
    end
  end

  def cast!(query, expr, message) do
    message =
      [message: message, query: query, file: expr.file, line: expr.line]
      |> Ecto.QueryError.exception()
      |> Exception.message

    raise Ecto.CastError, message: message
  end

  defp error!(query, message) do
    raise Ecto.QueryError, message: message, query: query
  end

  defp error!(query, expr, message) do
    raise Ecto.QueryError, message: message, query: query, file: expr.file, line: expr.line
  end
end
