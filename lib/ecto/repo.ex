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
  Fetches all results from the data store based on the given query.

  ## Example

      # Fetch all post titles
      query = from p in Post,
           select: post.title
      MyRepo.all(query)
  """
  defcallback all(term) :: { :ok, term } | { :error, term }

  @doc """
  Stores a single new entity in the data store and returns its stored
  representation.

  ## Example

      post = Post.new(title: "Ecto is great", text: "really, it is")
        |> MyRepo.create
  """
  defcallback create(Record.t) :: { :ok, Record.t } | { :error, term }

  @doc """
  Updates an entity using the primary key as key, if the entity has no primary
  key `Ecto.NoPrimaryKey` will be raised.

  ## Example

      [post] = from p in Post, where: p.id == 42
      post = post.title("New title")
      MyRepo.update(post)
  """
  defcallback update(Record.t) :: { :ok, Record.t } | { :error, term }

  @doc """
  Deletes an entity using the primary key as key, if the entity has no primary
  key `Ecto.NoPrimaryKey` will be raised.

  ## Example

      [post] = from p in Post, where: p.id == 42
      MyRepo.delete(post)
  """
  defcallback delete(Record.t) :: :ok | { :error, term }

  @doc false
  def start_link(module, adapter) do
    adapter.start_link(module)
  end

  @doc false
  def stop(module, adapter) do
    adapter.stop(module)
  end

  @doc false
  def all(module, adapter, query) do
    query = Ecto.Query.normalize(query)
    Ecto.Query.validate(query)
    adapter.all(module, query)
  end

  @doc false
  def create(module, adapter, entity) do
    adapter.create(module, entity)
  end

  @doc false
  def update(module, adapter, entity) do
    entity_module = elem(entity, 0)
    unless entity_module.__ecto__(:primary_key) do
      raise Ecto.NoPrimaryKey, entity: entity, reason: "can't be updated"
    end
    adapter.update(module, entity)
  end

  @doc false
  def delete(module, adapter, entity) do
    entity_module = elem(entity, 0)
    unless entity_module.__ecto__(:primary_key) do
      raise Ecto.NoPrimaryKey, entity: entity, reason: "can't be deleted"
    end
    adapter.delete(module, entity)
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
end
