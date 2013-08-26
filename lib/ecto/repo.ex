defmodule Ecto.Repo do
  @moduledoc """
  This module is used to define a repository. A repository maps to a data
  store, for example an SQL database. A repository must implement `url/0` and
  set an adapter (see `Ecto.Adapter`) to be used for the repository. All
  functions from the `Ecto.Adapter` module will be available on the repository
  module but without the first parameter.

  When used, the following options are allowed:

  * `:adapter` - the adapter to be used for the repository; it will be used 
                 to handle connections to the data store and to compile queries

  ## Example

      defmodule MyRepo do
        use Ecto.Repo, adapter: Ecto.Adapters.Postgres

        def url do
          "ecto://postgres:postgres@localhost/postgres"
        end
      end
  """

  use Behaviour

  alias Ecto.Queryable
  alias Ecto.Query.Query
  alias Ecto.Query.Util
  alias Ecto.Query.WhereBuilder
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.FromBuilder
  alias Ecto.Query.BuilderUtil

  @doc false
  defmacro __using__(opts) do
    adapter = Keyword.fetch!(opts, :adapter)

    quote do
      use unquote(adapter)
      @behaviour Ecto.Repo

      def start_link do
        Ecto.Repo.start_link(__MODULE__, unquote(adapter))
      end

      def stop do
        Ecto.Repo.stop(__MODULE__, unquote(adapter))
      end

      def get(queryable, id) do
        Ecto.Repo.get(__MODULE__, unquote(adapter), queryable, id)
      end

      def all(queryable) do
        Ecto.Repo.all(__MODULE__, unquote(adapter), queryable)
      end

      def create(entity) do
        Ecto.Repo.create(__MODULE__, unquote(adapter), entity)
      end

      def update(entity) do
        Ecto.Repo.update(__MODULE__, unquote(adapter), entity)
      end

      defmacro update_all(queryable, values) do
        Ecto.Repo.update_all(__MODULE__, unquote(adapter), queryable, values)
      end

      def delete(entity) do
        Ecto.Repo.delete(__MODULE__, unquote(adapter), entity)
      end

      def delete_all(queryable) do
        Ecto.Repo.delete_all(__MODULE__, unquote(adapter), queryable)
      end

      def adapter do
        unquote(adapter)
      end

      def query_apis do
        [ Ecto.Query.API ]
      end

      defoverridable [query_apis: 0]
    end
  end

  @doc """
  Should return the Ecto URL to be used for the repository. A URL is of the
  following format: `ecto://username:password@hostname:port/database?opts=123`
  where the `password`, `port` and `options` are optional. This function must be
  implemented by the user.
  """
  defcallback url() :: String.t

  @doc """
  Starts any connection pooling or supervision, if implemented by the adapter.
  """
  defcallback start_link() :: { :ok, pid } | :ok | { :error, term }

  @doc """
  Stops any connection pooling or supervision started with `start_link/1`.
  """
  defcallback stop() :: :ok

  @doc """
  Fetches a single entity from the data store where the primary key matches the
  given id. id should be an integer or a string that can be cast to an
  integer. Returns `nil` if no result was found. If the entity in the queryable
  has no primary key `Ecto.NoPrimaryKey` will be raised. `Ecto.AdapterError`
  will be raised if there is an adapter error.
  """
  defcallback get(Ecto.Queryable.t, integer) :: Record.t | nil | no_return

  @doc """
  Fetches all results from the data store based on the given query. May raise
  `Ecto.InvalidQuery` if query validation fails. `Ecto.AdapterError` will be
  raised if there is an adapter error.

  ## Example

      # Fetch all post titles
      query = from p in Post,
           select: post.title
      MyRepo.all(query)
  """
  defcallback all(Ecto.Query.t) :: [Record.t] | no_return

  @doc """
  Stores a single new entity in the data store and returns its stored
  representation. May raise `Ecto.AdapterError` if there is an adapter error.

  ## Example

      post = Post.new(title: "Ecto is great", text: "really, it is")
        |> MyRepo.create
  """
  defcallback create(Record.t) :: Record.t | no_return

  @doc """
  Updates an entity using the primary key as key. If the entity has no primary
  key `Ecto.NoPrimaryKey` will be raised. `Ecto.AdapterError` will be raised if
  there is an adapter error.

  ## Example

      [post] = from p in Post, where: p.id == 42
      post = post.title("New title")
      MyRepo.update(post)
  """
  defcallback update(Record.t) :: :ok | no_return

  @doc """
  Updates all entities matching the given query with the given values.
  `Ecto.AdapterError` will be raised if there is an adapter error.

  ## Examples

      MyRepo.update_all(Post, title: "New title")

      MyRepo.update_all(p in Post, visits: p.visits + 1)

      from(p in Post, where: p.id < 10) |>
        MyRepo.update_all(visits: title: "New title")
  """
  defmacrocallback update_all(Macro.t, Keyword.t) :: integer | no_return

  @doc """
  Deletes an entity using the primary key as key. If the entity has no primary
  key `Ecto.NoPrimaryKey` will be raised. `Ecto.AdapterError` will be raised if
  there is an adapter error.

  ## Example

      [post] = from p in Post, where: p.id == 42
      MyRepo.delete(post)
  """
  defcallback delete(Record.t) :: :ok | no_return

  @doc """
  Deletes all entities matching the given query with the given values.
  `Ecto.AdapterError` will be raised if there is an adapter error.

  ## Examples

      MyRepo.delete_all(Post)

      from(p in Post, where: p.id < 10) |> MyRepo.delete_all
  """
  defcallback delete_all(Ecto.Queryable.t) :: integer | no_return

  @doc false
  def start_link(repo, adapter) do
    adapter.start_link(repo)
  end

  @doc false
  def stop(repo, adapter) do
    adapter.stop(repo)
  end

  @doc false
  def get(repo, adapter, queryable, id) when is_binary(id) do
    # TODO: Check primary key type if we should do the casting
    get(repo, adapter, queryable, binary_to_integer(id))
  end

  def get(repo, adapter, queryable, id) when is_integer(id) do
    reason = "getting entity"

    query = Queryable.to_query(queryable)
    Util.validate_get(query, repo.query_apis)

    entity = query.from
    check_primary_key(entity, reason)
    primary_key = entity.__ecto__(:primary_key)

    quoted = quote do &0.unquote(primary_key) == unquote(id) end
    expr = QueryExpr[expr: quoted]
    query = Util.merge(query, :where, expr)
    query = Util.normalize(query)

    case adapter.all(repo, query) |> check_result(adapter, reason) do
      [entity] -> entity
      [] -> nil
      _ -> raise Ecto.NotSingleResult, entity: entity
    end
  end

  @doc false
  def all(repo, adapter, queryable) do
    query = Queryable.to_query(queryable)
    query = Util.normalize(query)
    Util.validate(query, repo.query_apis)
    reason = "fetching entities"
    result = adapter.all(repo, query) |> check_result(adapter, reason)

    if query.preloads == [] do
      result
    else
      preload(repo, query, result)
    end
  end

  @doc false
  def create(repo, adapter, entity) do
    reason = "creating an entity"
    validate_entity(entity, reason)
    primary_key = adapter.create(repo, entity) |> check_result(adapter, reason)

    if primary_key do
      entity.primary_key(primary_key)
    else
      entity
    end
  end

  @doc false
  def update(repo, adapter, entity) do
    reason = "updating an entity"
    check_primary_key(entity, reason)
    validate_entity(entity, reason)

    adapter.update(repo, entity)
      |> check_result(adapter, reason)
      |> check_single_result(entity)
  end

  @doc false
  def update_all(repo, adapter, queryable, values) do
    { binds, expr } = FromBuilder.escape(queryable)

    values = Enum.map(values, fn({ field, expr }) ->
      expr = BuilderUtil.escape(expr, binds)
      { field, expr }
    end)

    quote do
      values = unquote(values)
      repo = unquote(repo)

      query = Queryable.to_query(unquote(expr))
      query = Util.normalize(query, skip_select: true)
      Util.validate_update(query, repo.query_apis, values)

      reason = "updating entities"
      adapter = unquote(adapter)
      adapter.update_all(repo, query, values)
        |> Ecto.Repo.check_result(adapter, reason)
    end
  end

  @doc false
  def delete(repo, adapter, entity) do
    reason = "deleting an entity"
    check_primary_key(entity, reason)
    validate_entity(entity, reason)

    adapter.delete(repo, entity)
      |> check_result(adapter, reason)
      |> check_single_result(entity)
  end

  @doc false
  def delete_all(repo, adapter, queryable) do
    query = Queryable.to_query(queryable)
    query = Util.normalize(query, skip_select: true)
    Util.validate_delete(query, repo.query_apis)

    reason = "deleting entities"
    adapter.delete_all(repo, query) |> check_result(adapter, reason)
  end

  @doc false
  def parse_url(url, default_port) do
    info = URI.parse(url)

    unless info.scheme == "ecto" do
      raise Ecto.InvalidURL, url: url, reason: "not an ecto url"
    end

    unless is_binary(info.userinfo) and size(info.userinfo) > 0  do
      raise Ecto.InvalidURL, url: url, reason: "url has to contain a username"
    end

    unless info.path =~ %r"^/([^/])+$" do
      raise Ecto.InvalidURL, url: url, reason: "path should be a database name"
    end

    destructure [username, password], String.split(info.userinfo, ":")
    database = String.slice(info.path, 1, size(info.path))
    query = URI.decode_query(info.query || "") |> bindict_to_kw
    port = info.port || default_port

    opts = [
      username: username,
      hostname: info.host,
      database: database,
      port: port ]

    if password, do: opts = [password: password] ++ opts
    opts ++ query
  end

  defp bindict_to_kw(dict) do
    Enum.reduce(dict, [], fn({ k, v }, acc) ->
      [{ binary_to_atom(k), v } | acc]
    end)
  end

  @doc false
  def check_result(result, adapter, reason) do
    case result do
      :ok -> :ok
      { :ok, res } -> res
      { :error, err } ->
        raise Ecto.AdapterError, adapter: adapter, reason: reason, internal: err
    end
  end

  def check_single_result(result, entity) do
    unless result == 1 do
      module = elem(entity, 0)
      pk_field = module.__ecto__(:primary_key)
      pk_value = entity.primary_key
      raise Ecto.NotSingleResult, entity: module, primary_key: pk_field, id: pk_value
    end
    :ok
  end

  defp check_primary_key(entity, reason) when is_atom(entity) do
    unless entity.__ecto__(:primary_key) do
      raise Ecto.NoPrimaryKey, entity: entity, reason: reason
    end
  end

  defp check_primary_key(entity, reason) when is_record(entity) do
    module = elem(entity, 0)
    unless module.__ecto__(:primary_key) && entity.primary_key do
      raise Ecto.NoPrimaryKey, entity: entity, reason: reason
    end
  end

  defp validate_entity(entity, reason) do
    module = elem(entity, 0)
    primary_key = module.__ecto__(:primary_key)
    zipped = module.__ecto__(:entity_kw, entity)

    Enum.each(zipped, fn({ field, value }) ->
      type = module.__ecto__(:field_type, field)
      value_type = Util.value_to_type(value)

      valid = field == primary_key or
              value_type == nil or
              Util.type_eq?(value_type, type)

      # TODO: Check if entity field allows nil
      unless valid do
        raise Ecto.ValidationError, entity: entity, field: field,
          type: value_type, expected_type: type, reason: reason
      end
    end)
  end

  defp preload(repo, Query[] = query, results) do
    var = Util.from_entity_var(query)
    pos = Util.locate_var(query.select.expr, var)
    preloads = Enum.map(query.preloads, &(&1.expr)) |> List.concat

    Enum.reduce(preloads, results, fn field, acc ->
      Ecto.Preloader.run(repo, acc, field, pos)
    end)
  end
end
