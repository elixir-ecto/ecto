defmodule Ecto.DynamicRepo.ChildSupervisor do
  @moduledoc """
  """

  use Supervisor

  @defaults [timeout: 15000, pool_timeout: 5000]

  def start_link(repo, adapter, opts) do
    Supervisor.start_link(__MODULE__, {repo, adapter, opts}, name: repo)
  end

  def init({repo, adapter, opts}) do
    {:ok, config} = config(opts)
    children = [adapter.child_spec(Ecto.DynamicRepo, config)]
    if Keyword.get(opts, :query_cache_owner, true) do
      :ets.new(repo, [:set, :public, :named_table, read_concurrency: true])
    end
    supervise(children, strategy: :one_for_one)
  end

  def child_spec({repo, adapter, opts}) do
    %{
      id: repo,
      start: {__MODULE__, :start_link, [repo, adapter, opts]},
      type: :supervisor
    }
  end

  def config(config) do
    {url, config} =
      @defaults
      |> Keyword.merge(config)
      |> Keyword.pop(:url)

    {:ok, Keyword.merge(config, Ecto.Repo.Supervisor.parse_url(url || ""))}
  end
end
