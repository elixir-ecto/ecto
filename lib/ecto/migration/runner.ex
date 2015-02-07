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
  def run(repo, module, direction, operation, opts) do
    level = Keyword.get(opts, :log, :info)
    start_link(repo, direction, level)

    log(level, "== Running #{inspect module}.#{operation}/0 #{direction}")
    {time, _} = :timer.tc(module, operation, [])
    log(level, "== Migrated in #{inspect(div(time, 10000) / 10)}s")

    stop()
  end

  @doc """
  Starts the runner for the specified repo.
  """
  def start_link(repo, direction, level) do
    Agent.start_link(fn ->
      %{direction: direction, repo: repo,
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

  ## Helpers

  defp repo_and_direction_and_level do
    Agent.get(__MODULE__, fn %{repo: repo, direction: direction, level: level} ->
      {repo, direction, level}
    end)
  end

  defp execute_in_direction(repo, :forward, level, command) do
    log_ddl(level, command)
    repo.adapter.execute_ddl(repo, command, @opts)
  end

  defp execute_in_direction(repo, :backward, level, {:create, %Index{}=index}) do
    if repo.adapter.ddl_exists?(repo, index, @opts) do
      log_ddl(level, {:drop, index})
      repo.adapter.execute_ddl(repo, {:drop, index}, @opts)
    end
  end

  defp execute_in_direction(repo, :backward, level, command) do
    reversed = reverse(command)

    if reversed do
      log_ddl(level, reversed)
      repo.adapter.execute_ddl(repo, reversed, @opts)
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
  defp reverse({:alter,  %Table{}=table, changes}) do
    if reversed = reverse(changes) do
      {:alter, table, reversed}
    end
  end

  defp reverse(_), do: false

  ## Logging

  defp log_ddl(level, ddl) when is_binary(ddl),
    do: log(level, "execute #{inspect ddl}")

  defp log_ddl(level, {:create, %Table{} = table, _}),
    do: log(level, "create table #{table.name}")
  defp log_ddl(level, {:alter, %Table{} = table, _}),
    do: log(level, "alter table #{table.name}")
  defp log_ddl(level, {:drop, %Table{} = table}),
    do: log(level, "drop table #{table.name}")

  defp log_ddl(level, {:create, %Index{} = index}),
    do: log(level, "create index #{index.name}")
  defp log_ddl(level, {:drop, %Index{} = index}),
    do: log(level, "drop index #{index.name}")

  defp log(false, _msg), do: :ok
  defp log(level, msg),  do: Logger.log(level, msg)
end
