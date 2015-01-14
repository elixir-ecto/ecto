defmodule Ecto.Migration.Runner do
  @moduledoc """
  Runner is a gen server that's responsible for running migrations in either `:forward` or `:reverse` directions
  """
  use GenServer

  alias Ecto.Migration.Table
  alias Ecto.Migration.Index

  @doc """
  Starts the runner for the specified repo.
  """
  def start_link(repo) do
    state = %{direction: :forward,
              repo: repo,
              command: nil,
              elements: []}

    GenServer.start_link(__MODULE__, state, [name: __MODULE__])
  end

  def handle_call({:direction, direction}, _from, state) do
    {:reply, :ok, %{state | direction: direction}}
  end

  def handle_call({:execute, command}, _from, state) do
    response = execute_in_direction(state.repo, state.direction, command)

    {:reply, response, state}
  end

  def handle_call({:exists, command}, _from, state=%{direction: direction, repo: repo}) do
    exists = repo.adapter.object_exists?(repo, command)
    response = if direction == :forward, do: exists, else: !exists

    {:reply, response, state}
  end

  def handle_call({:start_command, command}, _from, state) do
    {:reply, :ok, %{state | command: command}}
  end

  def handle_call(:end_command, _from, state) do
    {operation, object} = state.command
    response = execute_in_direction(state.repo, state.direction, {operation, object, state.elements})

    {:reply, response, %{state | command: nil, elements: []}}
  end

  def handle_call({:add_element, element}, _from, state) do
    elements = state.elements ++ [element]

    {:reply, :ok, %{state | elements: elements}}
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
      :irreversible -> raise Ecto.MigrationError, message: "Cannot reverse migration command: #{inspect command}"
      response      -> response
    end
  end

  @doc """
  Start a command.
  """
  def start_command(command) do
    call({:start_command, command})
  end

  @doc """
  Executes and clears current command. Must call `create_command/1` first.
  """
  def end_command do
    call(:end_command)
  end

  @doc """
  Add an element to the current command. Must call `create_command/1` first.
  """
  def add_element(element) do
    call({:add_element, element})
  end

  @doc """
  Checks if a column, table or index exists
  """
  def exists?(type, object) do
    call {:exists, {type, object}}
  end

  defp call(message) do
    GenServer.call(__MODULE__, message)
  end

  defp execute_in_direction(repo, :forward, command) do
    repo.adapter.execute_migration(repo, command)
  end

  defp execute_in_direction(repo, :reverse, command) do
    reversed = reverse(command)

    if reversed do
      repo.adapter.execute_migration(repo, reversed)
    else
      :irreversible
    end
  end

  defp reverse([]),   do: []
  defp reverse([h|t]) do
    if reversed = reverse(h) do
      [reversed|reverse(t)]
    end
  end

  defp reverse({:create, %Table{}=table, _columns}), do: {:drop, table}
  defp reverse({:create, %Index{}=index}),           do: {:drop, index}
  defp reverse({:add,    name, _type, _opts}),       do: {:remove, name}
  defp reverse({:rename, from, to}),                 do: {:rename, to, from}
  defp reverse({:alter,  %Table{}=table, changes}) do
    if reversed = reverse(changes) do
      {:alter, table, reversed}
    end
  end

  defp reverse(_), do: false
end
