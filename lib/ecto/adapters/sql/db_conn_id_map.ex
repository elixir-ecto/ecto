defmodule Ecto.Adapters.SQL.DBConnIdMap do
  @moduledoc ~S"""
  Map between Ecto connection processes and DB backend connections. Allows to correlate
  DB log entries (which show the backend connection id) with Elixir log entries (where we can
  output the DB connection id and not the Ecto connection pid).
  """

  @name __MODULE__
  @table :db_conn_id_map

  use GenServer

  def register(conn_pid, conn_id) do
    :ok = GenServer.call(@name, {:register, conn_pid, conn_id})
  end

  def fetch(conn_pid) do
    case :ets.lookup(@table, conn_pid) do
      [{_, conn_id}] -> {:ok, conn_id}
      [] -> :error
    end
  end

  def start_link do
    GenServer.start_link(__MODULE__, [], name: @name)
  end

  def init([]) do
    :ets.new(@table, [:set, :named_table, :protected, read_concurrency: true])
    {:ok, nil}
  end

  def handle_call({:register, conn_pid, conn_id}, _from, state) do
    IO.puts "DBConnIdMap registered: conn_pid=#{inspect conn_pid} conn_id=#{inspect conn_id}"
    :ets.insert(@table, {conn_pid, conn_id})
    Process.monitor(conn_pid)
    {:reply, :ok, state}
  end

  def handle_call(request, from, state) do
    super(request, from, state)
  end

  def handle_cast(request, state) do
    super(request, state)
  end

  def handle_info({:DOWN, _ref, :process, conn_pid, _reason}, state) do
    IO.puts "DBConnIdMap conn died: conn_pid=#{inspect conn_pid}"
    :ets.delete(@table, conn_pid)
    {:noreply, state}
  end

  def handle_info(info, state) do
    super(info, state)
  end
end
