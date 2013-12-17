defmodule Ecto.Migration.DslTest do
  use ExUnit.Case

  alias Ecto.Migration.Ast.Table
  alias Ecto.Migration.Ast.Index

  import Ecto.Migration.Dsl

  defmodule MockMigrationRunner do
    use GenServer.Behaviour

    def start_link do
      :gen_server.start_link({:local, :migration_runner}, __MODULE__, [], [])
    end

    def handle_call({:run, command}, _from, state) do
      {:reply, {:executed, command}, state}
    end
  end

  setup do
    MockMigrationRunner.start_link
    :ok
  end

  test "executing" do
    assert execute("a response") == {:executed, "a response"}
  end

  test "creating table" do
    response = create table(:products, key: true) do
      add :name, :string
      timestamps
    end

    assert response == {:executed, {:create, Table[name: :products, key: true],
                        [{:add, :id, :primary_key, []},
                         {:add, :name, :string, []},
                         {:add, :created_at, :datetime, []},
                         {:add, :updated_at, :datetime, []}]}}
  end

  test "dropping table" do
    response = drop table(:products)

    assert response == {:executed, {:drop, Table.new(name: :products)}}
  end

  test "creating index" do
    response = create index(:products, [:name], unique: true)

    assert response == {:executed, {:create, Index.new(table: :products, columns: [:name], unique: true)}}
  end

  test "dropping index" do
    response = drop index([:name], on: :products)

    assert response == {:executed, {:drop, Index.new(table: :products, columns: [:name], unique: nil)}}
  end

  test "alter table" do
    response = alter table(:products) do
      add :name, :string, default: 'Untitled'
      modify :price, :integer, default: 99
      remove :summary
      rename :name, :title
    end

    assert response == {:executed, {:alter, Table[name: :products],
                        [{:add, :name, :string, [default: 'Untitled']},
                         {:modify, :price, :integer, [default: 99]},
                         {:remove, :summary},
                         {:rename, :name, :title}]}}
  end
end
