defmodule Ecto.Repo.Backend do
  # The backend invoked by user defined repos.
  @moduledoc false

  alias Ecto.Queryable
  alias Ecto.Query.Util
  alias Ecto.Query.FromBuilder
  alias Ecto.Query.BuilderUtil
  require Ecto.Query, as: Q

  def start_link(repo, adapter) do
    Enum.each(repo.query_apis, &Code.ensure_loaded(&1))
    adapter.start_link(repo, parse_url(repo.url))
  end

  def stop(repo, adapter) do
    adapter.stop(repo)
  end

  def get(repo, adapter, queryable, id) do
    query       = Queryable.to_query(queryable)
    entity      = query.from |> Util.entity
    primary_key = entity.__entity__(:primary_key)

    Util.validate_get(query, repo.query_apis)
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
                   limit: 1) |> Util.normalize

    case adapter.all(repo, query) do
      [entity] -> entity
      [] -> nil
      _ -> raise Ecto.NotSingleResult, entity: entity
    end
  end

  def all(repo, adapter, queryable) do
    query = Queryable.to_query(queryable) |> Util.normalize
    Util.validate(query, repo.query_apis)
    adapter.all(repo, query)
  end

  def create(repo, adapter, entity) do
    validate_entity(entity)
    adapter.create(repo, entity)
  end

  def update(repo, adapter, entity) do
    check_primary_key(entity)
    validate_entity(entity)

    adapter.update(repo, entity) |> check_single_result(entity)
  end

  def update_all(repo, adapter, queryable, values) do
    { binds, expr } = FromBuilder.escape(queryable)

    values = Enum.map(values, fn({ field, expr }) ->
      expr = BuilderUtil.escape(expr, binds)
      { field, expr }
    end)

    quote do
      Ecto.Repo.Backend.runtime_update_all(unquote(repo),
        unquote(adapter), unquote(expr), unquote(values))
    end
  end

  def runtime_update_all(repo, adapter, queryable, values) do
    query = Queryable.to_query(queryable) |> Util.normalize(skip_select: true)
    Util.validate_update(query, repo.query_apis, values)
    adapter.update_all(repo, query, values)
  end

  def delete(repo, adapter, entity) do
    check_primary_key(entity)
    validate_entity(entity)

    adapter.delete(repo, entity) |> check_single_result(entity)
  end

  def delete_all(repo, adapter, queryable) do
    query = Queryable.to_query(queryable) |> Util.normalize(skip_select: true)
    Util.validate_delete(query, repo.query_apis)
    adapter.delete_all(repo, query)
  end

  def transaction(repo, adapter, fun) when is_function(fun, 0) do
    adapter.transaction(repo, fun)
  end

  ## Helpers

  defp parse_url(url) do
  
    unless url =~ %r/^[^:\/?#\s]+:\/\// do
      raise Ecto.InvalidURL, url: url, reason: "url should start with a scheme, host should start with //"
    end

    info = URI.parse(url)

    unless is_binary(info.userinfo) and size(info.userinfo) > 0  do
      raise Ecto.InvalidURL, url: url, reason: "url has to contain a username"
    end

    unless info.path =~ %r"^/([^/])+$" do
      raise Ecto.InvalidURL, url: url, reason: "path should be a database name"
    end

    destructure [username, password], String.split(info.userinfo, ":")
    database = String.slice(info.path, 1, size(info.path))
    query = URI.decode_query(info.query || "", []) |> atomize_keys

    opts = [ username: username,
             hostname: info.host,
             database: database ]

    if password,  do: opts = [password: password] ++ opts
    if info.port, do: opts = [port: info.port] ++ opts

    opts ++ query
  end

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
    zipped = module.__entity__(:entity_kw, entity)

    Enum.each(zipped, fn({ field, value }) ->
      type = module.__entity__(:field_type, field)

      value_type = case Util.value_to_type(value) do
        { :ok, { vtype, { :ok, subvtype } } } -> { vtype, subvtype }
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
end
