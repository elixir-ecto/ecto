defmodule Ecto.Repo.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(repo, adapter, opts) do
    {name, opts} = Keyword.pop(opts, :name, repo)
    Supervisor.start_link(__MODULE__, {name, repo, adapter, opts}, [name: name])
  end

  def init({name, repo, adapter, opts}) do
    {default_pool, _, _} = repo.__pool__

    opts =
      opts
      |> Keyword.put_new(:pool, default_pool)
      |> Keyword.put_new(:pool_name, Module.concat(name, Pool))

    children = [
      supervisor(adapter, [repo, opts])
    ]

    :ets.new(repo, [:set, :public, :named_table, read_concurrency: true])
    supervise(children, strategy: :one_for_one)
  end
end
