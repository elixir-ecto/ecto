defmodule Ecto.Registry do
  @moduledoc false

  use GenServer

  ## Public interface

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__])
  end

  def associate(pid, value) when is_pid(pid) do
    GenServer.call(__MODULE__, {:associate, pid, value})
  end

  def lookup(repo_name) do
    pid = GenServer.whereis(repo_name)
    :ets.lookup_element(__MODULE__, pid, 3)
  end

  ## Callbacks

  def init(:ok) do
    table = :ets.new(__MODULE__, [:named_table, read_concurrency: true])
    {:ok, table}
  end

  def handle_call({:associate, pid, value}, _from, table) do
    ref = Process.monitor(pid)
    true = :ets.insert(table, {pid, ref, value})
    {:reply, :ok, table}
  end

  def handle_info({:DOWN, ref, _type, pid, _reason}, table) do
    [{^pid, ^ref, _}] = :ets.lookup(table, pid)
    :ets.delete(table, pid)
    {:noreply, table}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
