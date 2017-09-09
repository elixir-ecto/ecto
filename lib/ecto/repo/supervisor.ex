defmodule Ecto.Repo.Supervisor do
  @moduledoc false
  use Supervisor

  @defaults [timeout: 15000, pool_timeout: 5000]
  @integer_url_query_params ["timeout", "pool_size", "pool_timeout"]

  @doc """
  Starts the repo supervisor.
  """
  def start_link(repo, otp_app, adapter, opts) do
    name = Keyword.get(opts, :name, repo)
    Supervisor.start_link(__MODULE__, {repo, otp_app, adapter, opts}, [name: name])
  end

  @doc """
  Retrieves the runtime configuration.
  """
  def runtime_config(type, repo, otp_app, custom) do
    if config = Application.get_env(otp_app, repo) do
      config = [otp_app: otp_app, repo: repo] ++
               (@defaults |> Keyword.merge(config) |> Keyword.merge(custom))

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

    case Keyword.get(config, :url) do
      {:system, env} = url ->
        IO.warn """
        Using #{inspect url} for your :url configuration is deprecated.

        Instead define an init/2 callback in your repository that sets
        the URL accordingly from your system environment:

            def init(_type, config) do
              {:ok, Keyword.put(config, :url, System.get_env(#{inspect env}))}
            end
        """
      _ ->
        :ok
    end

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

      "ecto://username:password@hostname:port/database?ssl=true&timeout=1000"

  """
  def parse_url(""), do: []

  def parse_url({:system, env}) when is_binary(env) do
    parse_url(System.get_env(env) || "")
  end

  def parse_url(url) when is_binary(url) do
    info = URI.parse(url)

    if is_nil(info.host) do
      raise Ecto.InvalidURLError, url: url, message: "host is not present"
    end

    if is_nil(info.path) or not (info.path =~ ~r"^/([^/])+$") do
      raise Ecto.InvalidURLError, url: url, message: "path should be a database name"
    end

    destructure [username, password], info.userinfo && String.split(info.userinfo, ":")
    "/" <> database = info.path

    url_opts = [username: username,
                password: password,
                database: database,
                hostname: info.host,
                port:     info.port]

    query_opts = parse_uri_query(info)

    for {k, v} <- url_opts ++ query_opts, not is_nil(v), do: {k, if(is_binary(v), do: URI.decode(v), else: v)}
  end

  defp parse_uri_query(%URI{query: nil}),
    do: []
  defp parse_uri_query(%URI{query: query} = url) do
    query
    |> URI.query_decoder()
    |> Enum.reduce([], fn
      {"ssl", "true"}, acc ->
        [{:ssl, true}] ++ acc

      {"ssl", "false"}, acc ->
        [{:ssl, false}] ++ acc

      {key, value}, acc when key in @integer_url_query_params ->
        [{String.to_atom(key), parse_integer!(key, value, url)}] ++ acc

      {key, _value}, _acc ->
        raise Ecto.InvalidURLError, url: url, message: "unsupported query parameter `#{key}`"
    end)
  end

  defp parse_integer!(key, value, url) do
    case Integer.parse(value) do
      {int, ""} ->
        int
      _ ->
        raise Ecto.InvalidURLError, url: url, message: "can not parse value `#{value}` for parameter `#{key}` as an integer"
    end
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
