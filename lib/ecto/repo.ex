defmodule Ecto.Repo do
  @moduledoc """
  This module is used to define a repository. A repository will map to a data
  store, for example an SQL database. A repository have to implement `url/0` and
  set an adapter (see `Ecto.Adapter`) to be used for the repository. All
  functions from the `Ecto.Adapter` module will be available on the repositoty
  module but without the first parameter.

  When used, it allows the following options:

  * `:adapter` - the adapter to be used for the repository, it will be used to
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

      def all(query) do
        Ecto.Repo.all(__MODULE__, unquote(adapter), query)
      end

      def create(entity) do
        Ecto.Repo.create(__MODULE__, unquote(adapter), entity)
      end

      def update(entity) do
        Ecto.Repo.update(__MODULE__, unquote(adapter), entity)
      end

      def delete(entity) do
        Ecto.Repo.delete(__MODULE__, unquote(adapter), entity)
      end

      def adapter do
        unquote(adapter)
      end
    end
  end

  @doc """
  Should return the Ecto URL to be used for the repository. A URL is of the
  following format: `ecto://username:password@hostname:port/database?opts=123`
  where the password, port and options are optional.
  """
  defcallback url() :: String.t

  @doc """
  Starts any connection pooling or supervision if the adapter implements that.
  """
  defcallback start_link() :: { :ok, pid } | :ok | { :error, term }

  @doc """
  Stops any connection pooling or supervision started with `start_link/1`.
  """
  defcallback stop() :: :ok

  @doc """
  Fetches all results from the data store based on the given query. May raise
  `Ecto.InvalidQuery` if query validation fails or `Ecto.AdapterError` if there
  is an adapter error.

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
  key `Ecto.NoPrimaryKey` will be raised or raise `Ecto.AdapterError` if there
  is an adapter error.

  ## Example

      [post] = from p in Post, where: p.id == 42
      post = post.title("New title")
      MyRepo.update(post)
  """
  defcallback update(Record.t) :: :ok | no_return

  @doc """
  Deletes an entity using the primary key as key. If the entity has no primary
  key `Ecto.NoPrimaryKey` will be raised or raise `Ecto.AdapterError` if there
  is an adapter error.

  ## Example

      [post] = from p in Post, where: p.id == 42
      MyRepo.delete(post)
  """
  defcallback delete(Record.t) :: :ok | no_return

  @doc false
  def start_link(repo, adapter) do
    adapter.start_link(repo)
  end

  @doc false
  def stop(repo, adapter) do
    adapter.stop(repo)
  end

  @doc false
  def all(repo, adapter, query) do
    query = Ecto.Query.normalize(query)
    Ecto.Query.validate(query)
    reason = "fetching entities"
    adapter.all(repo, query) |> check_result(adapter, reason)
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
    adapter.update(repo, entity) |> check_result(adapter, reason)
  end

  @doc false
  def delete(repo, adapter, entity) do
    reason = "deleting an entity"
    check_primary_key(entity, reason)
    validate_entity(entity, reason)
    adapter.delete(repo, entity) |> check_result(adapter, reason)
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

  defp check_result(result, adapter, reason) do
    case result do
      :ok -> :ok
      { :ok, res } -> res
      { :error, err } ->
        raise Ecto.AdapterError, adapter: adapter, reason: reason, internal: err
    end
  end

  defp check_primary_key(entity, reason) do
    module = elem(entity, 0)
    unless module.__ecto__(:primary_key) && entity.primary_key do
      raise Ecto.NoPrimaryKey, entity: entity, reason: reason
    end
  end

  defp validate_entity(entity, reason) do
    [module|values] = tuple_to_list(entity)
    primary_key = module.__ecto__(:primary_key)
    zipped = Enum.zip(values, module.__ecto__(:field_names))

    Enum.each(zipped, fn({ value, field }) ->
      type = module.__ecto__(:field_type, field)
      unless field == primary_key or check_value_type(value, type) do
        raise Ecto.ValidationError, entity: entity, field: field,
          type: type(value), expected_type: type, reason: reason
      end
    end)
  end

  defp check_value_type(value, :boolean) when is_boolean(value), do: true
  defp check_value_type(value, :string) when is_binary(value), do: true
  defp check_value_type(value, :integer) when is_integer(value), do: true
  defp check_value_type(value, :float) when is_float(value), do: true
  defp check_value_type(_value, _type), do: false

  defp type(value) when is_boolean(value), do: :boolean
  defp type(value) when is_binary(value), do: :string
  defp type(value) when is_integer(value), do: :integer
  defp type(value) when is_float(value), do: :float
  defp type(_value), do: :unknown
end
