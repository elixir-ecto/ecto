defmodule Ecto.Repo.Supervisor do
  @moduledoc false

  use Supervisor

  @doc """
  Starts the repo supervisor.
  """
  def start_link(repo, otp_app, adapter, opts) do
    name = opts[:name] || Application.get_env(otp_app, repo)[:name] || repo
    Supervisor.start_link(__MODULE__, {name, repo, otp_app, adapter, opts}, [name: name])
  end

  @doc """
  Retrieves and normalizes the configuration for `repo` in `otp_app`.
  """
  def config(repo, otp_app, custom) do
    if config = Application.get_env(otp_app, repo) do
      config = Keyword.merge(config, custom)
      {url, config} = Keyword.pop(config, :url)
      [otp_app: otp_app, repo: repo] ++ Keyword.merge(config, parse_url(url || ""))
    else
      raise ArgumentError,
        "configuration for #{inspect repo} not specified in #{inspect otp_app} environment"
    end
  end

  @doc """
  Parses the OTP configuration for compile time.
  """
  def parse_config(repo, opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    config  = Application.get_env(otp_app, repo, [])
    adapter = opts[:adapter] || config[:adapter]

    unless adapter do
      raise ArgumentError, "missing :adapter configuration in " <>
                           "config #{inspect otp_app}, #{inspect repo}"
    end

    unless Code.ensure_loaded?(adapter) do
      raise ArgumentError, "adapter #{inspect adapter} was not compiled, " <>
                           "ensure it is correct and it is included as a project dependency"
    end

    {otp_app, adapter, pool(repo, config), config}
  end

  defp pool(repo, config) do
    pool         = Keyword.get(config, :pool, Ecto.Pools.Poolboy)
    name         = Keyword.get(config, :pool_name, default_pool_name(repo, config))
    pool_timeout = Keyword.get(config, :pool_timeout, 5_000)
    timeout      = Keyword.get(config, :timeout, 15_000)
    {pool, name, pool_timeout, timeout}
  end

  defp default_pool_name(repo, config) do
    Module.concat(Keyword.get(config, :name, repo), Pool)
  end

  @doc """
  Parses an Ecto URL allowed in configuration.

  The format must be:

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

    if is_nil(info.host) do
      raise Ecto.InvalidURLError, url: url, message: "host is not present"
    end

    if is_nil(info.path) or not (info.path =~ ~r"^/([^/])+$") do
      raise Ecto.InvalidURLError, url: url, message: "path should be a database name"
    end

    if info.userinfo do
      destructure [username, password], String.split(info.userinfo, ":")
    end

    "/" <> database = info.path

    opts = [username: username,
            password: password,
            database: database,
            hostname: info.host,
            port:     info.port]

    Enum.reject(opts, fn {_k, v} -> is_nil(v) end)
  end

  ## Callbacks

  def init({name, repo, otp_app, adapter, opts}) do
    opts = config(repo, otp_app, opts)
    {default_pool, _, _, _} = repo.__pool__

    opts =
      opts
      |> Keyword.delete(:name)
      |> Keyword.put_new(:pool, default_pool)
      |> Keyword.put_new(:pool_name, Module.concat(name, Pool))

    children = [
      supervisor(adapter, [repo, opts])
    ]

    if Keyword.get(opts, :query_cache_owner, repo == repo.__query_cache__) do
      :ets.new(repo.__query_cache__, [:set, :public, :named_table, read_concurrency: true])
    end

    supervise(children, strategy: :one_for_one)
  end
end
