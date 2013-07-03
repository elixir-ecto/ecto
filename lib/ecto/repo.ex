defmodule Ecto.Repo do
  use Behaviour

  defmacro __using__(_opts) do
    quote do
      @behaviour Ecto.Repo
    end
  end

  defcallback url() :: String.t

  # TODO: Add behaviour for default_port in Ecto.Adapter

  def parse_url(url) do
    info = URI.parse(url)

    unless String.starts_with?(info.scheme, "ecto+") do
      raise Ecto.InvalidURL, url: url, reason: "not an ecto url"
    end

    unless info.userinfo =~ ":" do
      raise Ecto.InvalidURL, url: url, reason: "url has to contain username and password"
    end

    unless info.path =~ %r"^/([^/])+$" do
      raise Ecto.InvalidURL, url: url, reason: "path should be a database name"
    end

    "ecto+" <> adapter = info.scheme
    adapter_module = Module.concat([Ecto, Adapter, String.capitalize(adapter)])
    [username, password] = String.split(info.userinfo, ":")
    database = String.slice(info.path, 1, size(info.path))
    opts = URI.decode_query(info.query || "")
    port = info.port || adapter_module.default_port()

    [ adapter: adapter_module,
      username: username,
      password: password,
      hostname: info.host,
      database: database,
      port: port,
      opts: opts ]
  end
end
