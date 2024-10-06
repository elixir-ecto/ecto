defmodule Ecto.Repo.Registry do
  @moduledoc false

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def associate(pid, name, value) when is_pid(pid) do
    GenServer.call(__MODULE__, {:associate, pid, name, value})
  end

  def all_running() do
    for [pid, name] <- :ets.match(__MODULE__, {:"$1", :_, :"$2", :_}) do
      name || pid
    end
  end

  def lookup(repo) when is_atom(repo) do
    :persistent_term.get(repo, nil) ||
      raise "could not lookup Ecto repo #{inspect(repo)} because it was not started or it does not exist"
  end

  def lookup(pid) when is_pid(pid) do
    :ets.lookup_element(__MODULE__, pid, 4)
  end

  ## Callbacks

  @impl true
  def init(:ok) do
    table = :ets.new(__MODULE__, [:named_table, read_concurrency: true])
    {:ok, table}
  end

  @impl true
  def handle_call({:associate, pid, name, value}, _from, table) do
    ref = Process.monitor(pid)
    name && :persistent_term.put(name, value)
    true = :ets.insert(table, {pid, ref, name, value})
    {:reply, :ok, table}
  end

  @impl true
  def handle_info({:DOWN, ref, _type, pid, _reason}, table) do
    [{^pid, ^ref, name, _}] = :ets.lookup(table, pid)
    name && :persistent_term.erase(name)
    :ets.delete(table, pid)
    {:noreply, table}
  end
end
