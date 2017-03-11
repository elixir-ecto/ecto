defmodule Ecto.Repo.Supervisor do
  @moduledoc false
  use Supervisor

  @doc """
  Starts the repo supervisor.
  """
  def start_link(repo, otp_app, adapter, opts) do
    name = opts[:name] || repo
    Supervisor.start_link(__MODULE__, {repo, otp_app, adapter, opts}, [name: name])
  end

  @doc """
  Retrieves the runtime configuration.
  """
  def runtime_config(type, repo, otp_app, custom) do
    if config = Application.get_env(otp_app, repo) do
      config = [otp_app: otp_app, repo: repo] ++ Keyword.merge(config, custom)

      case repo_init(type, repo, config) do
        {:ok, config} ->
          {url, config} = Keyword.pop(config, :url)
          {:ok, Keyword.merge(config, parse_url(url || ""))}
        :ignore ->
          :ignore
      end
    else
      raise ArgumentError,
        "configuration for #{inspect repo} not specified in #{inspect otp_app} environment"
    end
  end

  defp repo_init(type, repo, config) do
    if Code.ensure_loaded?(repo) and function_exported?(repo, :init, 2) do
      repo.init(type, config)
    else
      {:ok, config}
    end
  end

  @doc """
  Retrieves the compile time configuration.
  """
  def compile_config(repo, opts) do
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

    {otp_app, adapter, config}
  end

  @doc """
  Parses an Ecto URL allowed in configuration.

  The format must be:

      "ecto://username:password@hostname:port/database"

  or

      {:system, "DATABASE_URL"}

  """
  # TODO: Deprecate `{:system, _}` in favor of `init/2`
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

    destructure [username, password], info.userinfo && String.split(info.userinfo, ":")
    "/" <> database = info.path

    opts = [username: username,
            password: password,
            database: database,
            hostname: info.host,
            port:     info.port]

    Enum.reject(opts, fn {_k, v} -> is_nil(v) end)
  end

  ## Callbacks

  def init({repo, otp_app, adapter, opts}) do
    case runtime_config(:supervisor, repo, otp_app, opts) do
      {:ok, opts} ->
        children = [adapter.child_spec(repo, opts)]
        if Keyword.get(opts, :query_cache_owner, true) do
          :ets.new(repo, [:set, :public, :named_table, read_concurrency: true])
        end
        supervise(children, strategy: :one_for_one)
      :ignore ->
        :ignore
    end
  end
end
