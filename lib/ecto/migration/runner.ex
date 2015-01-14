defmodule Ecto.Migration.Runner do
  # A GenServer responsible for running migrations
  # in either `:forward` or `:reverse` directions.
  @moduledoc false

  use GenServer

  alias Ecto.Migration.Table
  alias Ecto.Migration.Index

  @doc """
  Starts the runner for the specified repo.
  """
  def start_link(repo, direction) do
    Agent.start_link(fn ->
      %{direction: direction, repo: repo,
        command: nil, subcommands: []}
    end, name: __MODULE__)
  end

  @doc """
  Stops the runner.
  """
  def stop() do
    Agent.stop(__MODULE__)
  end

  @doc """
  Executes command tuples or strings.

  Ecto.MigrationError will be raised when the server
  is in `:reverse` direction and `command` is irreversible.
  """
  def execute(command) do
    {repo, direction} = repo_and_direction()
    execute_in_direction(repo, direction, command)
  end

  @doc """
  Starts a command.
  """
  def start_command(command) do
    Agent.update __MODULE__, &put_in(&1.command, command)
  end

  @doc """
  Executes and clears current command. Must call `start_command/1` first.
  """
  def end_command do
    command =
      Agent.get_and_update __MODULE__, fn state ->
        {operation, object} = state.command
        {{operation, object, Enum.reverse(state.subcommands)},
         %{state | command: nil, subcommands: []}}
      end
    execute(command)
  end

  @doc """
  Adds a subcommand to the current command. Must call `start_command/1` first.
  """
  def subcommand(subcommand) do
    reply =
      Agent.get_and_update(__MODULE__, fn
        %{command: nil} = state ->
          {:error, state}
        state ->
          {:ok, update_in(state.subcommands, &[subcommand|&1])}
      end)

    case reply do
      :ok ->
        :ok
      :error ->
        raise Ecto.MigrationError, message: "cannot execute command outside of block"
    end
  end

  @doc """
  Checks if a table or index exists.
  """
  def exists?(object) do
    {repo, direction} = repo_and_direction()
    exists = repo.adapter.object_exists?(repo, object)
    if direction == :forward, do: exists, else: !exists
  end

  defp repo_and_direction do
    Agent.get(__MODULE__, fn %{repo: repo, direction: direction} ->
      {repo, direction}
    end)
  end

  defp execute_in_direction(repo, :forward, command) do
    repo.adapter.execute_migration(repo, command)
  end

  defp execute_in_direction(repo, :reverse, command) do
    reversed = reverse(command)

    if reversed do
      repo.adapter.execute_migration(repo, reversed)
    else
      raise Ecto.MigrationError, message: "cannot reverse migration command: #{inspect command}"
    end
  end

  defp reverse([]),   do: []
  defp reverse([h|t]) do
    if reversed = reverse(h) do
      [reversed|reverse(t)]
    end
  end

  defp reverse({:create, %Index{}=index}),           do: {:drop, index}
  defp reverse({:drop,   %Index{}=index}),           do: {:create, index}
  defp reverse({:create, %Table{}=table, _columns}), do: {:drop, table}
  defp reverse({:add,    name, _type, _opts}),       do: {:remove, name}
  defp reverse({:rename, from, to}),                 do: {:rename, to, from}
  defp reverse({:alter,  %Table{}=table, changes}) do
    if reversed = reverse(changes) do
      {:alter, table, reversed}
    end
  end

  defp reverse(_), do: false
end
