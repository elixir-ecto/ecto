defmodule Ecto.Migration.Runner do
  # A GenServer responsible for running migrations
  # in either `:forward` or `:backward` directions.
  @moduledoc false
  require Logger

  alias Ecto.Migration.Table
  alias Ecto.Migration.Index
  alias Ecto.Migration.Constraint
  alias Ecto.Migration.Command

  @doc """
  Runs the given migration.
  """
  def run(repo, module, direction, operation, migrator_direction, opts) do
    level = Keyword.get(opts, :log, :info)
    sql = Keyword.get(opts, :log_sql, false)
    log = %{level: level, sql: sql}
    args  = [self(), repo, direction, migrator_direction, log]

    {:ok, runner} = Supervisor.start_child(Ecto.Migration.Supervisor, args)
    metadata(runner, opts)

    log(level, "== Running #{inspect module}.#{operation}/0 #{direction}")
    {time1, _} = :timer.tc(module, operation, [])
    {time2, _} = :timer.tc(&flush/0, [])
    time = time1 + time2
    log(level, "== Migrated in #{inspect(div(time, 100_000) / 10)}s")

    stop()
  end

  @doc """
  Stores the runner metadata.
  """
  def metadata(runner, opts) do
    prefix = opts[:prefix]
    Process.put(:ecto_migration, %{runner: runner, prefix: prefix && to_string(prefix)})
  end

  @doc """
  Starts the runner for the specified repo.
  """
  def start_link(parent, repo, direction, migrator_direction, log) do
    Agent.start_link(fn ->
      Process.link(parent)
      %{direction: direction, repo: repo, migrator_direction: migrator_direction,
        command: nil, subcommands: [], log: log, commands: [], config: repo.config()}
    end)
  end

  @doc """
  Stops the runner.
  """
  def stop() do
    Agent.stop(runner())
  end

  @doc """
  Accesses the given repository configuration.
  """
  def repo_config(key, default) do
    Agent.get(runner(), &Keyword.get(&1.config, key, default))
  end

  @doc """
  Returns the migrator command (up or down).

    * forward + up: up
    * forward + down: down
    * forward + change: up
    * backward + change: down

  """
  def migrator_direction do
    Agent.get(runner(), & &1.migrator_direction)
  end

  @doc """
  Gets the prefix for this migration
  """
  def prefix do
    case Process.get(:ecto_migration) do
      %{prefix: prefix} -> prefix
      _ -> raise "could not find migration runner process for #{inspect self()}"
    end
  end

  @doc """
  Executes queue migration commands.

  Reverses the order commands are executed when doing a rollback
  on a change/0 function and resets commands queue.
  """
  def flush do
    %{commands: commands, direction: direction} = Agent.get_and_update(runner(), fn (state) ->
      {state, %{state | commands: []}}
    end)

    commands  = if direction == :backward, do: commands, else: Enum.reverse(commands)

    for command <- commands do
      {repo, direction, log} = runner_config()
      execute_in_direction(repo, direction, log, command)
    end
  end

  @doc """
  Queues command tuples or strings for execution.

  Ecto.MigrationError will be raised when the server
  is in `:backward` direction and `command` is irreversible.
  """
  def execute(command) do
    Agent.update runner(), fn state ->
      %{state | command: nil, subcommands: [], commands: [command|state.commands]}
    end
  end

  @doc """
  Starts a command.
  """
  def start_command(command) do
    Agent.update runner(), &put_in(&1.command, command)
  end

  @doc """
  Queues and clears current command. Must call `start_command/1` first.
  """
  def end_command do
    Agent.update runner(), fn state ->
      {operation, object} = state.command
      command = {operation, object, Enum.reverse(state.subcommands)}
      %{state | command: nil, subcommands: [], commands: [command|state.commands]}
    end
  end

  @doc """
  Adds a subcommand to the current command. Must call `start_command/1` first.
  """
  def subcommand(subcommand) do
    reply =
      Agent.get_and_update(runner(), fn
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

  ## Execute
  @creates [:create, :create_if_not_exists]

  defp execute_in_direction(repo, :forward, log, %Command{up: up}) do
    log_and_execute_ddl(repo, log, up)
  end

  defp execute_in_direction(repo, :forward, log, command) do
    log_and_execute_ddl(repo, log, command)
  end

  defp execute_in_direction(repo, :backward, log, %Command{down: down}) do
    log_and_execute_ddl(repo, log, down)
  end

  defp execute_in_direction(repo, :backward, log, command) do
    if reversed = reverse(command) do
      log_and_execute_ddl(repo, log, reversed)
    else
      raise Ecto.MigrationError, message:
        "cannot reverse migration command: #{command command}. " <>
        "You will need to explicitly define up/1 and down/1 in your migration"
    end
  end

  defp reverse({command, %Index{} = index}) when command in @creates,
    do: {:drop, index}
  defp reverse({:drop, %Index{} = index}),
    do: {:create, index}

  defp reverse({command, %Table{} = table, _columns}) when command in @creates,
    do: {:drop, table}
  defp reverse({:alter,  %Table{} = table, changes}) do
    if reversed = table_reverse(changes, []) do
      {:alter, table, reversed}
    end
  end
  defp reverse({:rename, %Table{} = table_current, %Table{} = table_new}),
    do: {:rename, table_new, table_current}
  defp reverse({:rename, %Table{} = table, current_column, new_column}),
    do: {:rename, table, new_column, current_column}

  defp reverse({command, %Constraint{} = constraint}) when command in @creates,
    do: {:drop, constraint}
  defp reverse(_command), do: false

  defp table_reverse([{:add, name, _type, _opts} | t], acc) do
    table_reverse(t, [{:remove, name} | acc])
  end
  defp table_reverse([_ | _], _acc) do
    false
  end
  defp table_reverse([], acc) do
    acc
  end

  ## Helpers

  defp runner do
    case Process.get(:ecto_migration) do
      %{runner: runner} -> runner
      _ -> raise "could not find migration runner process for #{inspect self()}"
    end
  end

  defp runner_config do
    Agent.get(runner(), fn %{repo: repo, direction: direction, log: log} ->
      {repo, direction, log}
    end)
  end

  defp log_and_execute_ddl(repo, %{level: level, sql: sql}, command) do
    log(level, command(command))
    repo.__adapter__.execute_ddl(repo, command, [timeout: :infinity, log: sql])
  end

  defp log(false, _msg), do: :ok
  defp log(level, msg),  do: Logger.log(level, msg)

  defp command(ddl) when is_binary(ddl) or is_list(ddl),
    do: "execute #{inspect ddl}"

  defp command({:create, %Table{} = table, _}),
    do: "create table #{quote_name(table.prefix, table.name)}"
  defp command({:create_if_not_exists, %Table{} = table, _}),
    do: "create table if not exists #{quote_name(table.prefix, table.name)}"
  defp command({:alter, %Table{} = table, _}),
    do: "alter table #{quote_name(table.prefix, table.name)}"
  defp command({:drop, %Table{} = table}),
    do: "drop table #{quote_name(table.prefix, table.name)}"
  defp command({:drop_if_exists, %Table{} = table}),
    do: "drop table if exists #{quote_name(table.prefix, table.name)}"

  defp command({:create, %Index{} = index}),
    do: "create index #{quote_name(index.prefix, index.name)}"
  defp command({:create_if_not_exists, %Index{} = index}),
    do: "create index if not exists #{quote_name(index.prefix, index.name)}"
  defp command({:drop, %Index{} = index}),
    do: "drop index #{quote_name(index.prefix, index.name)}"
  defp command({:drop_if_exists, %Index{} = index}),
    do: "drop index if exists #{quote_name(index.prefix, index.name)}"
  defp command({:rename, %Table{} = current_table, %Table{} = new_table}),
    do: "rename table #{quote_name(current_table.prefix, current_table.name)} to #{quote_name(new_table.prefix, new_table.name)}"
  defp command({:rename, %Table{} = table, current_column, new_column}),
    do: "rename column #{current_column} to #{new_column} on table #{quote_name(table.prefix, table.name)}"

  defp command({:create, %Constraint{check: nil, exclude: nil}}),
    do: raise ArgumentError, "a constraint must have either a check or exclude option"
  defp command({:create, %Constraint{check: check, exclude: exclude}}) when is_binary(check) and is_binary(exclude),
    do: raise ArgumentError, "a constraint must not have both check and exclude options"
  defp command({:create, %Constraint{check: check} = constraint}) when is_binary(check),
    do: "create check constraint #{constraint.name} on table #{quote_name(constraint.prefix, constraint.table)}"
  defp command({:create, %Constraint{exclude: exclude} = constraint}) when is_binary(exclude),
    do: "create exclude constraint #{constraint.name} on table #{quote_name(constraint.prefix, constraint.table)}"
  defp command({:drop, %Constraint{} = constraint}),
    do: "drop constraint #{constraint.name} from table #{quote_name(constraint.prefix, constraint.table)}"

  defp quote_name(nil, name), do: quote_name(name)
  defp quote_name(prefix, name), do: quote_name(prefix) <> "." <> quote_name(name)
  defp quote_name(name) when is_atom(name), do: quote_name(Atom.to_string(name))
  defp quote_name(name), do: name
end
