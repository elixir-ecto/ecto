defmodule Ecto.Repo.Backend do
  # The backend invoked by user defined repos.
  @moduledoc false

  alias Ecto.Queryable
  alias Ecto.Query.Util
  alias Ecto.Query.Builder.From
  alias Ecto.Query.Builder
  alias Ecto.Query.Planner
  alias Ecto.Model.Callbacks

  require Ecto.Query

  ## Pool related

  def start_link(repo, adapter) do
    adapter.start_link(repo, repo.conf)
  end

  def stop(repo, adapter) do
    adapter.stop(repo)
  end

  ## Queries related

  def all(repo, adapter, queryable, opts) do
    {query, params} = Queryable.to_query(queryable) |> Planner.plan(%{})
    results = adapter.all(repo, query, params, opts)
    preload(repo, query, results)
  end

  def get(repo, adapter, queryable, id, opts) do
    one(repo, adapter, prepare_get(queryable, id), opts)
  end

  def get!(repo, adapter, queryable, id, opts) do
    one!(repo, adapter, prepare_get(queryable, id), opts)
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

  def update_all(repo, adapter, queryable, values, opts) do
    {binds, expr} = From.escape(queryable)

    {updates, params} =
      Enum.map_reduce(values, %{}, fn {field, expr}, params ->
        {expr, params} = Builder.escape(expr, {0, field}, params, binds)
        {{field, expr}, params}
      end)

    params = Builder.escape_params(params)

    quote do
      Ecto.Repo.Backend.update_all(unquote(repo), unquote(adapter),
        unquote(expr), unquote(updates), unquote(params), unquote(opts))
    end
  end

  # The runtime callback for update all.
  def update_all(repo, adapter, queryable, updates, params, opts) do
    # TODO: Those parameters should be properly cast
    params = for {k, {v, _type}} <- params, into: %{}, do: {k, v}
    {query, params} = Queryable.to_query(queryable)
                      |> Planner.plan(params, only_where: true)
    adapter.update_all(repo, query, updates, params, opts)
  end

  def delete_all(repo, adapter, queryable, opts) do
    {query, params} = Queryable.to_query(queryable)
                      |> Planner.plan(%{}, only_where: true)
    adapter.delete_all(repo, query, params, opts)
  end

  ## Transaction related

  def transaction(repo, adapter, opts, fun) when is_function(fun, 0) do
    adapter.transaction(repo, opts, fun)
  end

  def rollback(repo, adapter, value) do
    adapter.rollback(repo, value)
  end

  ## Model related

  def insert(repo, adapter, model, opts) do
    normalized_model = normalize_model model
    validate_model(normalized_model)

    with_transactions_if_callbacks repo, adapter, model, opts,
                                   ~w(before_insert after_insert)a, fn ->
      model    = Callbacks.__apply__(model, :before_insert)
      result   = adapter.insert(repo, model, opts)
      module   = model.__struct__
      pk_field = module.__schema__(:primary_key)
      if pk_field && (pk_value = Dict.get(result, pk_field)) do
        model = Ecto.Model.put_primary_key(model, pk_value)
      end

      struct(model, result)
      |> Callbacks.__apply__(:after_insert)
    end
  end

  def update(repo, adapter, model, opts) do
    normalized_model = normalize_model model
    check_primary_key(normalized_model)
    validate_model(normalized_model)

    with_transactions_if_callbacks repo, adapter, model, opts,
                                   ~w(before_update after_update)a, fn ->
      model  = Callbacks.__apply__(model, :before_update)
      single =
        adapter.update(repo, model, opts)
        |> check_single_result(model)

      Callbacks.__apply__(model, :after_update)
      single
    end
  end

  def delete(repo, adapter, model, opts) do
    normalized_model = normalize_model model

    check_primary_key(normalized_model)
    validate_model(normalized_model)

    with_transactions_if_callbacks repo, adapter, model, opts,
                                   ~w(before_delete after_delete)a, fn ->
      model  = Callbacks.__apply__(model, :before_delete)
      single =
        adapter.delete(repo, model, opts)
        |> check_single_result(model)

      Callbacks.__apply__(model, :after_delete)
      single
    end
  end

  ## Helpers

  # TODO: Test the error message
  defp preload(_repo, %{preloads: []}, results), do: results
  defp preload(repo, query, results) do
    var      = {:&, [], [0]}
    expr     = query.select.expr
    preloads = Enum.concat(query.preloads)

    cond do
      is_var?(expr, var) ->
        Ecto.Associations.Preloader.run(results, repo, preloads)
      pos = select_var(expr, var) ->
        Ecto.Associations.Preloader.run(results, repo, preloads, pos)
      true ->
        message = "source in from expression needs to be directly selected " <>
                  "when using preload or inside a single tuple or list"
        raise Ecto.QueryError, message: message, query: query
    end
  end

  defp is_var?({:assoc, _, [expr, _right]}, var),
    do: expr == var
  defp is_var?(expr, var),
    do: expr == var

  defp select_var({left, right}, var),
    do: select_var({:{}, [], [left, right]}, var)
  defp select_var({:{}, _, list}, var),
    do: select_var(list, var)
  defp select_var(list, var) when is_list(list),
    do: Enum.find_index(list, &is_var?(&1, var))
  defp select_var(_, _),
    do: nil

  defp prepare_get(queryable, id) do
    query = Queryable.to_query(queryable)

    model =
      case query.from do
        {_source, model} when model != nil ->
          model
        _ ->
          raise Ecto.QueryError, message: "cannot get an entry when query has no model in from",
                                 query: query
      end

    primary_key = model.__schema__(:primary_key)
    id          = normalize_primary_key(model, primary_key, id)

    check_primary_key(model)
    validate_primary_key(model, primary_key, id)
    Ecto.Query.from(x in query, where: field(x, ^primary_key) == ^id)
  end

  defp check_single_result(result, model) do
    unless result == 1 do
      module = model.__struct__
      pk_field = module.__schema__(:primary_key)
      pk_value = Map.get(model, pk_field)
      raise Ecto.NotSingleResult, model: module, primary_key: pk_field, id: pk_value, results: result
    end
    :ok
  end

  defp check_primary_key(model) when is_atom(model) do
    unless model.__schema__(:primary_key) do
      raise Ecto.NoPrimaryKey, model: model
    end
  end

  defp check_primary_key(model) when is_map(model) do
    module = model.__struct__
    pk_field = module.__schema__(:primary_key)
    pk_value = Map.get(model, pk_field)
    unless module.__schema__(:primary_key) && pk_value do
      raise Ecto.NoPrimaryKey, model: module
    end
  end

  defp validate_model(model) do
    module      = model.__struct__
    primary_key = module.__schema__(:primary_key)
    zipped      = module.__schema__(:keywords, model)

    Enum.each(zipped, fn {field, value} ->
      field_type = module.__schema__(:field_type, field)

      value_type = case Util.params_to_type(value) do
        {:ok, vtype} -> vtype
        {:error, reason} -> raise ArgumentError, message: reason
      end

      valid = field == primary_key or
              value_type == nil or
              Util.type_eq?(value_type, field_type)

      # TODO: Check if model field allows nil
      unless valid do
        raise Ecto.InvalidModel, model: model, field: field,
          type: value_type, expected_type: field_type
      end
    end)
  end

  defp validate_primary_key(model, primary_key, id) do
    field_type = model.__schema__(:field_type, primary_key)

    value_type = case Util.params_to_type(id) do
      {:ok, vtype} -> vtype
      {:error, reason} -> raise ArgumentError, message: reason
    end

    unless value_type == nil or Util.type_eq?(value_type, field_type) do
      raise Ecto.InvalidModel, model: model, field: primary_key,
        type: value_type, expected_type: field_type
    end
  end

  defp normalize_primary_key(model, primary_key, id) do
    type = model.__schema__(:field_type, primary_key)
    Util.try_cast(id, type)
  end

  defp normalize_model(model) do
    module = model.__struct__
    fields = module.__schema__(:field_names)

    Enum.reduce(fields, model, fn field, model ->
      type = module.__schema__(:field_type, field)
      Map.update!(model, field, &Util.try_cast(&1, type))
    end)
  end

  defp with_transactions_if_callbacks(repo, adapter, model, opts, callbacks, fun) do
    struct = model.__struct__
    if Enum.any?(callbacks, &function_exported?(struct, &1, 1)) do
      {:ok, value} = transaction(repo, adapter, opts, fun)
      value
    else
      fun.()
    end
  end
end
