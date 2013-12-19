defmodule Ecto.Migration.Runner do
  @moduledoc """
  Runner is a gen server that's responsible for running migrations in either `:forward` or `:reverse` directions
  """
  use GenServer.Behaviour

  alias Ecto.Migration.Table
  alias Ecto.Migration.Index

  @server_name :migration_runner
  @full_name {:local, @server_name}

  @doc """
  Starts the runner for the specified repo.
  """
  def start_link(repo) do
    :gen_server.start_link(@full_name, __MODULE__, {:forward, repo}, [])
  end

  def handle_call({:direction, direction}, _from, {_, repo}) do
    {:reply, :ok, {direction, repo}}
  end

  def handle_call({:execute, command}, _from, state={:forward, repo}) do
    {:reply, repo.adapter.execute_migration(repo, command), state}
  end

  def handle_call({:execute, command}, _from, state={:reverse, repo}) do
    reversed = reverse(command)

    if reversed do
      {:reply, repo.adapter.execute_migration(repo, reversed), state}
    else
      {:reply, :irreversible, state}
    end
  end

  @doc """
  Changes the direction to run commands.
  """
  def direction(direction) do
    call {:direction, direction}
  end

  @doc """
  Executes command tuples or strings.
  Ecto.MigrationError will be raised when the server is in `:reverse` direction and `command` is irreversible
  """
  def execute(command) do
    case call {:execute, command} do
      :irreversible -> raise Ecto.MigrationError.new(message: "Cannot reverse migration command: #{inspect command}")
      response      -> response
    end
  end

  defp call(message) do
    :gen_server.call(@server_name, message)
  end

  defp reverse([]),   do: []
  defp reverse([h|t]) do
    if reversed = reverse(h) do
      [reversed|reverse(t)]
    end
  end

  defp reverse({:create, Table[]=table, _columns}), do: {:drop, table}
  defp reverse({:create, Index[]=index}),           do: {:drop, index}
  defp reverse({:add,    name, _type, _opts}),      do: {:remove, name}
  defp reverse({:rename, from, to}),                do: {:rename, to, from}
  defp reverse({:alter,  Table[]=table, changes}) do
    if reversed = reverse(changes) do
      {:alter, table, reversed}
    end
  end

  defp reverse(_), do: false
end
