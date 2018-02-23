defmodule Ecto.DynamicRepo.Supervisor do
  use DynamicSupervisor

  @defaults [timeout: 15000, pool_timeout: 5000]

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, [], name: name)
  end

  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def runtime_config(type, repo, otp_app, custom) do
    if config = Application.get_env(otp_app, repo) do
      config = [otp_app: otp_app, repo: repo] ++
        (@defaults |> Keyword.merge(config) |> Keyword.merge(custom))

      case repo_init(type, repo, config) do
        {:ok, config} ->
          {url, config} = Keyword.pop(config, :url)
          {:ok, Keyword.merge(config, Ecto.Repo.Supervisor.parse_url(url || ""))}

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

  def start_child(repo, name, otp_app, opts) do
    case runtime_config(:supervisor, repo, otp_app, opts) do
      {:ok, opts} ->
        :ets.new(name, [:set, :public, :named_table, read_concurrency: true])
        DynamicSupervisor.start_child(__MODULE__, {repo, Keyword.put(opts, :name, name)})

      :ignore ->
        :ignore
    end
  end
end
