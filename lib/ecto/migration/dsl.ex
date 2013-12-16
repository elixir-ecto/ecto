defmodule Ecto.Migration.Dsl do

  defmodule MigrationRunner do
    use GenServer.Behaviour

    @server_name :migration_runner
    @full_name {:local, @server_name}

    def run(command) do
      :gen_server.call(@server_name, {:run, command})
    end
  end

  alias Ecto.Migration.Ast.Table
  alias Ecto.Migration.Ast.Index

  defmacro create(object, do: block) do
    commands = case block do
      {:__block__, _location, ops} -> ops
      _ -> [block]
    end

    quote do
      Table[key: key] = unquote(object)
      id = if key, do: [add(:id, :primary_key)], else: []
      execute {:create, unquote(object), id ++ unquote(commands) |> List.flatten}
    end
  end

  defmacro alter(object, do: block) do
    commands = case block do
      {:__block__, _location, ops} -> ops
      _ -> [block]
    end

    quote do
      execute {:alter, unquote(object), unquote(commands) |> List.flatten}
    end
  end

  def create(object) do
    execute {:create, object}
  end

  def drop(object) do
    execute {:drop, object}
  end

  def table(name, opts // []) do
    Table.new(name: name, key: Dict.get(opts, :key, true))
  end

  def index(columns, opts=[on: table]) do
    Index.new(table: table, columns: columns, unique: opts[:unique])
  end

  def index(table, columns, opts // []) do
    Index.new(table: table, columns: columns, unique: opts[:unique])
  end

  def execute(command) do
    MigrationRunner.run command
  end

  def add(column, type, opts // []) do
    {:add, column, type, opts}
  end

  def timestamps do
    [add(:created_at, :datetime), add(:updated_at, :datetime)]
  end
end
