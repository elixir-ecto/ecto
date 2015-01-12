defmodule Ecto.Repo.Config do
  @moduledoc false

  @doc """
  Retrieves and normalizes the configuration for `repo` in `otp_app`.
  """
  def config(otp_app, module) do
    if config = Application.get_env(otp_app, module) do
      {url, config} = Keyword.pop(config, :url)
      [otp_app: otp_app] ++ Keyword.merge(config, parse_url(url || ""))
    else
      raise ArgumentError,
        "configuration for #{inspect module} not specified in #{inspect otp_app}"
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
    info = URI.parse(url)

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

    Enum.reject(opts, fn {_k, v} -> is_nil(v) end) ++
      atomize_keys(URI.decode_query(info.query || ""))
  end

  defp atomize_keys(dict) do
    Enum.map dict, fn {k, v} -> {String.to_atom(k), v} end
  end
end
