defmodule Ecto.Repo do
  use Behaviour

  defmacro __using__(opts) do
    adapter = Keyword.fetch!(opts, :adapter)

    quote do
      use unquote(adapter)
      @behaviour Ecto.Repo

      def start do
        unquote(adapter).start(__MODULE__)
      end

      def query(query) do
        unquote(adapter).query(__MODULE__, query)
      end

      defp adapter do
        unquote(adapter)
      end
    end
  end

  defcallback url() :: String.t

  def parse_url(url, default_port) do
    info = URI.parse(url)

    unless info.scheme == "ecto" do
      raise Ecto.InvalidURL, url: url, reason: "not an ecto url"
    end

    unless info.userinfo =~ ":" do
      raise Ecto.InvalidURL, url: url, reason: "url has to contain username and password"
    end

    unless info.path =~ %r"^/([^/])+$" do
      raise Ecto.InvalidURL, url: url, reason: "path should be a database name"
    end

    [username, password] = String.split(info.userinfo, ":")
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
