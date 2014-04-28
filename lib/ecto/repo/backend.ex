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
    entity      = query.from |> Util.entity
    primary_key = entity.__entity__(:primary_key)

    Validator.validate_get(query, repo.query_apis)
    check_primary_key(entity)

    case Util.value_to_type(id) do
      { :ok, _ } -> :ok
      { :error, reason } -> raise ArgumentError, message: reason
    end

    # TODO: Maybe it would indeed be better to emit a direct AST
    # instead of building it up so we don't need to pass through
    # normalization and what not.
    query = Q.from(x in query,
                   where: field(x, ^primary_key) == ^id,
                   limit: 1) |> Normalizer.normalize

    case adapter.all(repo, query, opts) do
      [entity] -> entity
      [] -> nil
      _ -> raise Ecto.NotSingleResult, entity: entity
    end
  end

  def all(repo, adapter, queryable, opts) do
    query = Queryable.to_query(queryable) |> Normalizer.normalize
    Validator.validate(query, repo.query_apis)
    adapter.all(repo, query, opts)
  end

  def insert(repo, adapter, entity, opts) do
    normalized_entity = normalize_entity(entity)
    validate_entity(normalized_entity)
    adapter.insert(repo, normalized_entity, opts) |> entity.update
  end

  def update(repo, adapter, entity, opts) do
    entity = normalize_entity(entity)
    check_primary_key(entity)
    validate_entity(entity)

    adapter.update(repo, entity, opts) |> check_single_result(entity)
  end

  def update_all(repo, adapter, queryable, values, opts) do
    { binds, expr } = FromBuilder.escape(queryable)

    values = Enum.map(values, fn({ field, expr }) ->
      expr = BuilderUtil.escape(expr, binds)
      { field, expr }
    end)

    quote do
      Ecto.Repo.Backend.runtime_update_all(unquote(repo), unquote(adapter),
        unquote(expr), unquote(values), unquote(opts))
    end
  end

  def runtime_update_all(repo, adapter, queryable, values, opts) do
    query = Queryable.to_query(queryable) |> Normalizer.normalize(skip_select: true)
    Validator.validate_update(query, repo.query_apis, values)
    adapter.update_all(repo, query, values, opts)
  end

  def delete(repo, adapter, entity, opts) do
    entity = normalize_entity(entity)
    check_primary_key(entity)
    validate_entity(entity)

    adapter.delete(repo, entity, opts) |> check_single_result(entity)
  end

  def delete_all(repo, adapter, queryable, opts) do
    query = Queryable.to_query(queryable) |> Normalizer.normalize(skip_select: true)
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
    Enum.map dict, fn({ k, v }) -> { binary_to_atom(k), v } end
  end

  defp check_single_result(result, entity) do
    unless result == 1 do
      module = elem(entity, 0)
      pk_field = module.__entity__(:primary_key)
      pk_value = entity.primary_key
      raise Ecto.NotSingleResult, entity: module, primary_key: pk_field, id: pk_value
    end
    :ok
  end

  defp check_primary_key(entity) when is_atom(entity) do
    unless entity.__entity__(:primary_key) do
      raise Ecto.NoPrimaryKey, entity: entity
    end
  end

  defp check_primary_key(entity) when is_record(entity) do
    module = elem(entity, 0)
    unless module.__entity__(:primary_key) && entity.primary_key do
      raise Ecto.NoPrimaryKey, entity: entity
    end
  end

  defp validate_entity(entity) do
    module = elem(entity, 0)
    primary_key = module.__entity__(:primary_key)
    zipped = module.__entity__(:keywords, entity)

    Enum.each(zipped, fn({ field, value }) ->
      type = module.__entity__(:field_type, field)

      value_type = case Util.value_to_type(value) do
        { :ok, vtype } -> vtype
        { :error, reason } -> raise ArgumentError, message: reason
      end

      valid = field == primary_key or
              value_type == nil or
              Util.type_eq?(value_type, type)

      # TODO: Check if entity field allows nil
      unless valid do
        raise Ecto.InvalidEntity, entity: entity, field: field,
          type: value_type, expected_type: type
      end
    end)
  end

  defp normalize_entity(entity) do
    module = elem(entity, 0)
    fields = module.__entity__(:field_names)

    Enum.reduce(fields, entity, fn field, entity ->
      type = module.__entity__(:field_type, field)

      if Util.type_castable_to?(type) do
        value = apply(entity, field, []) |> Util.try_cast(type)
        apply(entity, field, [value])
      else
        entity
      end
    end)
  end
end
