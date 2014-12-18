defmodule Ecto.Repo.Backend do
  # The backend invoked by user defined repos.
  @moduledoc false

  alias Ecto.Queryable
  alias Ecto.Query.Util
  alias Ecto.Query.Builder.From
  alias Ecto.Query.Builder
  alias Ecto.Query.Normalizer
  alias Ecto.Query.Validator
  alias Ecto.Model.Callbacks
  require Ecto.Query, as: Q

  def start_link(repo, adapter) do
    adapter.start_link(repo, repo.conf)
  end

  def stop(repo, adapter) do
    adapter.stop(repo)
  end

  def get(repo, adapter, queryable, id, opts) do
    case do_get(repo, adapter, queryable, id, opts) do
      {_model, [one]} -> one
      {_model, []} -> nil
      {model, results} -> raise Ecto.NotSingleResult, model: model, results: length(results)
    end
  end

  def get!(repo, adapter, queryable, id, opts) do
    case do_get(repo, adapter, queryable, id, opts) do
      {_model, [one]} -> one
      {model, results} -> raise Ecto.NotSingleResult, model: model, results: length(results)
    end
  end

  defp do_get(repo, adapter, queryable, id, opts) do
    query       = Queryable.to_query(queryable)
    model       = query.from |> Util.model
    primary_key = model.__schema__(:primary_key)
    id          = normalize_primary_key(model, primary_key, id)

    Validator.validate_get(query)
    check_primary_key(model)
    validate_primary_key(model, primary_key, id)

    # TODO: Maybe it would indeed be better to emit a direct AST
    # instead of building it up so we don't need to pass through
    # normalization and what not.
    query = Q.from(x in query, where: field(x, ^primary_key) == ^id)
            |> Normalizer.normalize

    models = adapter.all(repo, query, opts)
    {model, models}
  end

  def one(repo, adapter, queryable, opts) do
    case do_one(repo, adapter, queryable, opts) do
      {_model, [one]} -> one
      {_model, []} -> nil
      {model, results} -> raise Ecto.NotSingleResult, model: model, results: length(results)
    end
  end

  def one!(repo, adapter, queryable, opts) do
    case do_one(repo, adapter, queryable, opts) do
      {_model, [one]} -> one
      {model, results} -> raise Ecto.NotSingleResult, model: model, results: length(results)
    end
  end

  defp do_one(repo, adapter, queryable, opts) do
    query  = Queryable.to_query(queryable) |> Normalizer.normalize
    model  = query.from |> Util.model
    Validator.validate(query)

    models = adapter.all(repo, query, opts)
    {model, models}
  end

  def all(repo, adapter, queryable, opts) do
    query = Queryable.to_query(queryable) |> Normalizer.normalize
    Validator.validate(query)
    adapter.all(repo, query, opts)
  end

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

  def update_all(repo, adapter, queryable, values, opts) do
    {binds, expr} = From.escape(queryable)

    {values, params} =
      Enum.map_reduce(values, %{}, fn {field, expr}, params ->
        {expr, params} = Builder.escape(expr, :boolean, params, binds)
        {{field, expr}, params}
      end)

    params = Builder.escape_params(params)

    quote do
      Ecto.Repo.Backend.runtime_update_all(unquote(repo), unquote(adapter),
        unquote(expr), unquote(values), unquote(params), unquote(opts))
    end
  end

  def runtime_update_all(repo, adapter, queryable, values, params, opts) do
    query = Queryable.to_query(queryable)
            |> Normalizer.normalize(skip_select: true)

    Validator.validate_update(query, values, params)
    adapter.update_all(repo, query, values, params, opts)
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

  def delete_all(repo, adapter, queryable, opts) do
    query = Queryable.to_query(queryable)
            |> Normalizer.normalize(skip_select: true)
    Validator.validate_delete(query)
    adapter.delete_all(repo, query, opts)
  end

  def transaction(repo, adapter, opts, fun) when is_function(fun, 0) do
    adapter.transaction(repo, opts, fun)
  end

  def rollback(repo, adapter, value) do
    adapter.rollback(repo, value)
  end

  ## Helpers

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
