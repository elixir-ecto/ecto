defmodule Ecto.Migration.BidirectionalRunner do
  use GenServer.Behaviour

  alias Ecto.Migration.Ast.Table
  alias Ecto.Migration.Ast.Index

  @server_name :migration_runner
  @full_name {:local, @server_name}

  def start_link do
    :gen_server.start_link(@full_name, __MODULE__, :up, [])
  end

  def handle_call({:direction, direction}, _from, _state) do
    {:reply, :ok, direction}
  end

  def handle_call({:run, command}, _from, :up) do
    {:reply, command, :up}
  end

  def handle_call({:run, command}, _from, :down) do
    {:reply, reverse(command), :down}
  end

  def direction(direction) do
    call {:direction, direction}
  end

  def run(command) do
    call {:run, command}
  end

  defp call(message) do
    :gen_server.call(@server_name, message)
  end

  defp reverse({:create, Table[]=table, _columns}), do: {:drop, table}
  defp reverse({:create, Index[]=index}),           do: {:drop, index}
  # TODO: rename, alter (add, rename)
  defp reverse(_), do: :not_reversable
end
