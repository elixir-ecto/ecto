defmodule Ecto.Migration.Runner do
  # A GenServer responsible for running migrations
  # in either `:forward` or `:backward` directions.
  @moduledoc false

  use GenServer
  require Logger

  alias Ecto.Migration.Table
  alias Ecto.Migration.Index

  @opts [timeout: :infinity, log: false]

  @doc """
  Runs the given migration.
  """
  def run(repo, module, direction, operation, migrator_direction, opts) do
    level = Keyword.get(opts, :log, :info)
    start_link(repo, direction, migrator_direction, level)

    log(level, "== Running #{inspect module}.#{operation}/0 #{direction}")
    {time, _} = :timer.tc(module, operation, [])
    log(level, "== Migrated in #{inspect(div(time, 10000) / 10)}s")

    stop()
  end

  @doc """
  Starts the runner for the specified repo.
  """
  def start_link(repo, direction, migrator_direction, level) do
    Agent.start_link(fn ->
      %{direction: direction, repo: repo, migrator_direction: migrator_direction,
        command: nil, subcommands: [], level: level}
    end, name: __MODULE__)
  end

  @doc """
  Stops the runner.
  """
  def stop() do
    Agent.stop(__MODULE__)
  end

  @doc """
  Returns the migrator command (up or down).

    * forward + up: up
    * forward + down: down
    * forward + change: up
    * backward + change: down

  """
  def migrator_direction do
    Agent.get(__MODULE__, & &1.migrator_direction)
  end

  @doc """
  Executes command tuples or strings.

  Ecto.MigrationError will be raised when the server
  is in `:backward` direction and `command` is irreversible.
  """
  def execute(command) do
    {repo, direction, level} = repo_and_direction_and_level()
    execute_in_direction(repo, direction, level, command)
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
    {repo, direction, _level} = repo_and_direction_and_level()
    exists = repo.adapter.ddl_exists?(repo, object, @opts)
    if direction == :forward, do: exists, else: !exists
  end

  ## Execute

  defp execute_in_direction(repo, :forward, level, command) do
    log_and_execute_ddl(repo, level, command)
  end

  defp execute_in_direction(repo, :backward, level, {:create, %Index{}=index}) do
    if repo.adapter.ddl_exists?(repo, index, @opts) do
      log_and_execute_ddl(repo, level, {:drop, index})
    end
  end

  defp execute_in_direction(repo, :backward, level, {:drop, %Index{}=index}) do
    log_and_execute_ddl(repo, level, {:create, index})
  end

  defp execute_in_direction(repo, :backward, level, command) do
    if reversed = reverse(command) do
      log_and_execute_ddl(repo, level, reversed)
    else
      raise Ecto.MigrationError, message: "cannot reverse migration command: #{command command}"
    end
  end

  defp reverse({:create, %Table{}=table, _columns}), do: {:drop, table}
  defp reverse({:alter,  %Table{}=table, changes}) do
    if reversed = table_reverse(changes) do
      {:alter, table, reversed}
    end
  end
  defp reverse(_command), do: false

  defp table_reverse([]),   do: []
  defp table_reverse([h|t]) do
    if reversed = table_reverse(h) do
      [reversed|table_reverse(t)]
    end
  end

  defp table_reverse({:add, name, _type, _opts}), do: {:remove, name}
  defp table_reverse(_), do: false

  ## Helpers

  defp repo_and_direction_and_level do
    Agent.get(__MODULE__, fn %{repo: repo, direction: direction, level: level} ->
      {repo, direction, level}
    end)
  end

  defp log_and_execute_ddl(repo, level, command) do
    log(level, command(command))
    repo.adapter.execute_ddl(repo, command, @opts)
  end

  defp log(false, _msg), do: :ok
  defp log(level, msg),  do: Logger.log(level, msg)

  defp command(ddl) when is_binary(ddl),
    do: "execute #{inspect ddl}"

  defp command({:create, %Table{} = table, _}),
    do: "create table #{table.name}"
  defp command({:alter, %Table{} = table, _}),
    do: "alter table #{table.name}"
  defp command({:drop, %Table{} = table}),
    do: "drop table #{table.name}"

  defp command({:create, %Index{} = index}),
    do: "create index #{index.name}"
  defp command({:drop, %Index{} = index}),
    do: "drop index #{index.name}"
end
