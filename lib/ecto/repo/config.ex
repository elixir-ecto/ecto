defmodule Ecto.Repo.Config do
  @moduledoc false

  @doc """
  Loads otp app and adapter configuration from options.
  """
  def parse(module, opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    config  = Application.get_env(otp_app, module, [])
    adapter = opts[:adapter] || config[:adapter]

    unless adapter do
      raise ArgumentError, "missing :adapter configuration in " <>
                           "config #{inspect otp_app}, #{inspect module}"
    end

    unless Code.ensure_loaded?(adapter) do
      raise ArgumentError, "adapter #{inspect adapter} was not compiled, " <>
                           "ensure it is correct and it is included as a project dependency"
    end

    {otp_app, adapter, config}
  end

  @doc """
  Retrieves and normalizes the configuration for `repo` in `otp_app`.
  """
  def config(otp_app, module) do
    if config = Application.get_env(otp_app, module) do
      {url, config} = Keyword.pop(config, :url)
      [otp_app: otp_app] ++ Keyword.merge(config, parse_url(url || ""))
    else
      raise ArgumentError,
        "configuration for #{inspect module} not specified in #{inspect otp_app} environment"
    end
  end

  @doc """
  Parses an Ecto URL. The format must be:

      "ecto://username:password@hostname:port/database"

  or

      {:system, "DATABASE_URL"}

  """
  def parse_url(""), do: []

  def parse_url({:system, env}) when is_binary(env) do
    parse_url(System.get_env(env) || "")
  end

  def parse_url(url) when is_binary(url) do
    info = url |> URI.decode() |> URI.parse()

    unless info.host do
      raise Ecto.InvalidURLError, url: url, message: "host is not present"
    end

    unless String.match? info.path, ~r"^/([^/])+$" do
      raise Ecto.InvalidURLError, url: url, message: "path should be a database name"
    end

    if info.userinfo do
      destructure [username, password], String.split(info.userinfo, ":")
    end

    database = String.slice(info.path, 1, String.length(info.path))

    opts = [username: username,
            password: password,
            database: database,
            hostname: info.host,
            port:     info.port]

    Enum.reject(opts, fn {_k, v} -> is_nil(v) end)
  end
end
