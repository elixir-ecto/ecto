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
        unquote(adapter).start_link(__MODULE__)
      end

      def fetch(query) do
        unquote(adapter).fetch(__MODULE__, query)
      end

      def create(entity) do
        unquote(adapter).create(__MODULE__, entity)
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
    opts = URI.decode_query(info.query || "") |> bindict_to_kw
    port = info.port || default_port

    [ username: username,
      password: password,
      hostname: info.host,
      database: database,
      port: port ] ++ opts
  end

  defp bindict_to_kw(dict) do
    Enum.reduce(dict, [], fn({ k, v }, acc) ->
      [{ binary_to_atom(k), v } | acc]
    end)
  end
end
