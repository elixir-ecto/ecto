defmodule Ecto.Repo.Backend do
  # The backend invoked by user defined repos.
  @moduledoc false

  alias Ecto.Queryable
  alias Ecto.Query.Util
  alias Ecto.Query.FromBuilder
  alias Ecto.Query.BuilderUtil
  alias Ecto.Query.Normalizer
  alias Ecto.Query.Validator
  require Ecto.Query, as: Q

  def storage_up(repo, adapter) do
    adapter.storage_up(repo.conf)
  end

  def storage_down(repo, adapter) do
    adapter.storage_down(repo.conf)
  end

  def start_link(repo, adapter) do
    Enum.each(repo.query_apis, &Code.ensure_loaded(&1))
    adapter.start_link(repo, repo.conf)
  end

  def stop(repo, adapter) do
    adapter.stop(repo)
  end

  def get(repo, adapter, queryable, id, opts) do
    query       = Queryable.to_query(queryable)
    model      = query.from |> Util.model
    primary_key = model.__schema__(:primary_key)

    Validator.validate_get(query, repo.query_apis)
    check_primary_key(model)

    case Util.value_to_type(id) do
      {:ok, _} -> :ok
      {:error, reason} -> raise ArgumentError, message: reason
    end

    # TODO: Maybe it would indeed be better to emit a direct AST
    # instead of building it up so we don't need to pass through
    # normalization and what not.
    query = Q.from(x in query,
                   where: field(x, ^primary_key) == ^id,
                   limit: 1) |> Normalizer.normalize

    case adapter.all(repo, query, opts) do
      [model] -> model
      [] -> nil
      _ -> raise Ecto.NotSingleResult, model: model
    end
  end

  def all(repo, adapter, queryable, opts) do
    query = Queryable.to_query(queryable) |> Normalizer.normalize
    Validator.validate(query, repo.query_apis)
    adapter.all(repo, query, opts)
  end

  def insert(repo, adapter, model, opts) do
    normalized_model = normalize_model(model)
    validate_model(normalized_model)

    result   = adapter.insert(repo, normalized_model, opts)
    module   = model.__struct__
    pk_field = module.__schema__(:primary_key)


    if pk_field do
      pk_value = Dict.get(result, pk_field) ||
                 Map.get(normalized_model, pk_field)
      model = Ecto.Model.put_primary_key(model, pk_value)
    end

    struct(model, result)
  end

  def update(repo, adapter, model, opts) do
    model = normalize_model(model)
    check_primary_key(model)
    validate_model(model)

    adapter.update(repo, model, opts)
    |> check_single_result(model)
  end

  def update_all(repo, adapter, queryable, values, opts) do
    {binds, expr} = FromBuilder.escape(queryable)

    values = Enum.map(values, fn({field, expr}) ->
      expr = BuilderUtil.escape(expr, binds)
      {field, expr}
    end)

    quote do
      Ecto.Repo.Backend.runtime_update_all(unquote(repo), unquote(adapter),
        unquote(expr), unquote(values), unquote(opts))
    end
  end

  def runtime_update_all(repo, adapter, queryable, values, opts) do
    query = Queryable.to_query(queryable)
            |> Normalizer.normalize(skip_select: true)
    Validator.validate_update(query, repo.query_apis, values)
    adapter.update_all(repo, query, values, opts)
  end

  def delete(repo, adapter, model, opts) do
    model = normalize_model(model)
    check_primary_key(model)
    validate_model(model)

    adapter.delete(repo, model, opts)
    |> check_single_result(model)
  end

  def delete_all(repo, adapter, queryable, opts) do
    query = Queryable.to_query(queryable)
            |> Normalizer.normalize(skip_select: true)
    Validator.validate_delete(query, repo.query_apis)
    adapter.delete_all(repo, query, opts)
  end

  def transaction(repo, adapter, opts, fun) when is_function(fun, 0) do
    adapter.transaction(repo, opts, fun)
  end

  def rollback(repo, adapter, value) do
    adapter.rollback(repo, value)
  end

  def parse_url(url) do
    unless String.match? url, ~r/^[^:\/?#\s]+:\/\// do
      raise Ecto.InvalidURL, url: url, reason: "url should start with a scheme, host should start with //"
    end

    info = URI.parse(url)

    unless is_binary(info.userinfo) and size(info.userinfo) > 0  do
      raise Ecto.InvalidURL, url: url, reason: "url has to contain a username"
    end

    unless String.match? info.path, ~r"^/([^/])+$" do
      raise Ecto.InvalidURL, url: url, reason: "path should be a database name"
    end

    destructure [username, password], String.split(info.userinfo, ":")
    database = String.slice(info.path, 1, size(info.path))
    query = URI.decode_query(info.query || "") |> atomize_keys

    opts = [ username: username,
             hostname: info.host,
             database: database ]

    if password,  do: opts = [password: password] ++ opts
    if info.port, do: opts = [port: info.port] ++ opts

    opts ++ query
  end

  ## Helpers

  defp atomize_keys(dict) do
    Enum.map dict, fn {k, v} -> {binary_to_atom(k), v} end
  end

  defp check_single_result(result, model) do
    unless result == 1 do
      module = model.__struct__
      pk_field = module.__schema__(:primary_key)
      pk_value = Map.get(model, pk_field)
      raise Ecto.NotSingleResult, model: module, primary_key: pk_field, id: pk_value
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
      raise Ecto.NoPrimaryKey, model: model
    end
  end

  defp validate_model(model) do
    module      = model.__struct__
    primary_key = module.__schema__(:primary_key)
    zipped      = module.__schema__(:keywords, model)

    Enum.each(zipped, fn {field, value} ->
      type = module.__schema__(:field_type, field)

      value_type = case Util.value_to_type(value) do
        {:ok, vtype} -> vtype
        {:error, reason} -> raise ArgumentError, message: reason
      end

      valid = field == primary_key or
              value_type == nil or
              Util.type_eq?(value_type, type)

      # TODO: Check if model field allows nil
      unless valid do
        raise Ecto.InvalidModel, model: model, field: field,
          type: value_type, expected_type: type
      end
    end)
  end

  defp normalize_model(model) do
    module = model.__struct__
    fields = module.__schema__(:field_names)

    Enum.reduce(fields, model, fn field, model ->
      type = module.__schema__(:field_type, field)

      if Util.type_castable_to?(type) do
        Map.update!(model, field, &Util.try_cast(&1, type))
      else
        model
      end
    end)
  end
end
