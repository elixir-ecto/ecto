defmodule Ecto.Migration.Runner do
  use GenServer.Behaviour

  alias Ecto.Migration.Table
  alias Ecto.Migration.Index

  @server_name :migration_runner
  @full_name {:local, @server_name}

  def start_link(repo) do
    :gen_server.start_link(@full_name, __MODULE__, {:up, repo}, [])
  end

  def handle_call({:direction, direction}, _from, {_, repo}) do
    {:reply, :ok, {direction, repo}}
  end

  def handle_call({:execute, command}, _from, state={:up, repo}) do
    {:reply, repo.adapter.execute_migration(repo, command), state}
  end

  def handle_call({:execute, command}, _from, state={:down, repo}) do
    reversed = reverse(command)

    if reversed do
      {:reply, repo.adapter.execute_migration(repo, reversed), state}
    else
      {:reply, :not_reversible, state}
    end
  end

  def direction(direction) do
    call {:direction, direction}
  end

  def execute(command) do
    call {:execute, command}
  end

  defp call(message) do
    :gen_server.call(@server_name, message)
  end

  defp reverse([]),    do: []
  defp reverse([h|t]), do: [reverse(h)|reverse(t)]
  defp reverse({:create, Table[]=table, _columns}), do: {:drop, table}
  defp reverse({:create, Index[]=index}),           do: {:drop, index}
  defp reverse({:add,    name, _type, _opts}),      do: {:remove, name}
  defp reverse({:rename, from, to}),                do: {:rename, to, from}
  defp reverse({:alter,  Table[]=table, changes}) do
    reversed = reverse(changes)

    if reversed |> Enum.all? &(&1) do
      {:alter, table, reversed}
    end
  end
  defp reverse(_), do: false
end
