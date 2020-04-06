defmodule Ecto.Repo.Supervisor do
  @moduledoc false
  use Supervisor

  @defaults [timeout: 15000, pool_size: 10]
  @integer_url_query_params ["timeout", "pool_size"]

  @doc """
  Starts the repo supervisor.
  """
  def start_link(repo, otp_app, adapter, opts) do
    sup_opts = if name = Keyword.get(opts, :name, repo), do: [name: name], else: []
    Supervisor.start_link(__MODULE__, {name, repo, otp_app, adapter, opts}, sup_opts)
  end

  @doc """
  Retrieves the runtime configuration.
  """
  def runtime_config(type, repo, otp_app, opts) do
    config = Application.get_env(otp_app, repo, [])
    config = [otp_app: otp_app] ++ (@defaults |> Keyword.merge(config) |> Keyword.merge(opts))
    config = Keyword.put_new_lazy(config, :telemetry_prefix, fn -> telemetry_prefix(repo) end)

    case repo_init(type, repo, config) do
      {:ok, config} ->
        validate_config!(repo, config)
        {url, config} = Keyword.pop(config, :url)
        {:ok, Keyword.merge(config, parse_url(url || ""))}

      :ignore ->
        :ignore
    end
  end

  defp telemetry_prefix(repo) do
    repo
    |> Module.split()
    |> Enum.map(& &1 |> Macro.underscore() |> String.to_atom())
  end

  defp repo_init(type, repo, config) do
    if Code.ensure_loaded?(repo) and function_exported?(repo, :init, 2) do
      repo.init(type, config)
    else
      {:ok, config}
    end
  end

  defp validate_config!(repo, config) do
    log = Keyword.get(config, :log, :debug)

    unless log in [false, :debug, :info, :warn, :error] do
      raise ArgumentError, "invalid :log configuration for #{inspect(repo)}, it should be " <>
                             "false, :debug, :info, :warn or :error, got: #{inspect(log)}"
    end
  end

  @doc """
  Retrieves the compile time configuration.
  """
  def compile_config(_repo, opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    adapter = opts[:adapter]

    unless adapter do
      raise ArgumentError, "missing :adapter option on use Ecto.Repo"
    end

    if Code.ensure_compiled(adapter) != {:module, adapter} do
      raise ArgumentError, "adapter #{inspect adapter} was not compiled, " <>
                           "ensure it is correct and it is included as a project dependency"
    end

    behaviours =
      for {:behaviour, behaviours} <- adapter.__info__(:attributes),
          behaviour <- behaviours,
          do: behaviour

    unless Ecto.Adapter in behaviours do
      raise ArgumentError,
            "expected :adapter option given to Ecto.Repo to list Ecto.Adapter as a behaviour"
    end

    {otp_app, adapter, behaviours}
  end

  @doc """
  Parses an Ecto URL allowed in configuration.

  The format must be:

      "ecto://username:password@hostname:port/database?ssl=true&timeout=1000"

  """
  def parse_url(""), do: []

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

    url_opts = [
      username: username,
      password: password,
      database: database,
      port: info.port
    ]

    url_opts = put_hostname_if_present(url_opts, info.host)
    query_opts = parse_uri_query(info)

    for {k, v} <- url_opts ++ query_opts,
        not is_nil(v),
        do: {k, if(is_binary(v), do: URI.decode(v), else: v)}
  end

  defp put_hostname_if_present(keyword, "") do
    keyword
  end

  defp put_hostname_if_present(keyword, hostname) when is_binary(hostname) do
    Keyword.put(keyword, :hostname, hostname)
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

      {key, value}, acc ->
        [{String.to_atom(key), value}] ++ acc
    end)
  end

  defp parse_integer!(key, value, url) do
    case Integer.parse(value) do
      {int, ""} ->
        int

      _ ->
        raise Ecto.InvalidURLError,
              url: url,
              message: "can not parse value `#{value}` for parameter `#{key}` as an integer"
    end
  end

  ## Callbacks

  @doc false
  def init({name, repo, otp_app, adapter, opts}) do
    case runtime_config(:supervisor, repo, otp_app, opts) do
      {:ok, opts} ->
        :telemetry.execute(
          [:ecto, :repo, :init],
          %{system_time: System.system_time()},
          %{repo: repo, opts: opts}
        )

        {:ok, child, meta} = adapter.init([repo: repo] ++ opts)
        cache = Ecto.Query.Planner.new_query_cache(name)
        meta = Map.merge(meta, %{repo: repo, cache: cache})
        child_spec = wrap_child_spec(child, [adapter, meta])
        Supervisor.init([child_spec], strategy: :one_for_one, max_restarts: 0)

      :ignore ->
        :ignore
    end
  end

  def start_child({mod, fun, args}, adapter, meta) do
    case apply(mod, fun, args) do
      {:ok, pid} ->
        meta = Map.put(meta, :pid, pid)
        Ecto.Repo.Registry.associate(self(), {adapter, meta})
        {:ok, pid}

      other ->
        other
    end
  end

  defp wrap_child_spec({id, start, restart, shutdown, type, mods}, args) do
    {id, {__MODULE__, :start_child, [start | args]}, restart, shutdown, type, mods}
  end

  defp wrap_child_spec(%{start: start} = spec, args) do
    %{spec | start: {__MODULE__, :start_child, [start | args]}}
  end
end
