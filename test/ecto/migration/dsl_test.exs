defmodule Ecto.Migration.DSLTest do
  use ExUnit.Case, async: false

  alias Ecto.Migration.Table
  alias Ecto.Migration.Index

  import Ecto.Migration.DSL

  defmodule MockRunner do
    use GenServer

    def start_link do
      GenServer.start_link(__MODULE__, [], [name: Ecto.Migration.Runner])
    end

    def handle_call({:execute, command}, _from, state) do
      {:reply, {:executed, command}, state}
    end
  end

  setup do
    {:ok, _} = MockRunner.start_link
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

    assert response == {:executed, {:create, %Table{name: :products, key: true},
                        [{:add, :id, :primary_key, []},
                         {:add, :name, :string, []},
                         {:add, :created_at, :datetime, []},
                         {:add, :updated_at, :datetime, []}]}}
  end

  test "dropping table" do
    response = drop table(:products)

    assert response == {:executed, {:drop, %Table{name: :products}}}
  end

  test "creating index" do
    response = create index(:products, [:name], unique: true)

    assert response == {:executed, {:create, %Index{table: :products, columns: [:name], unique: true}}}
  end

  test "dropping index" do
    response = drop index([:name], on: :products)

    assert response == {:executed, {:drop, %Index{table: :products, columns: [:name], unique: nil}}}
  end

  test "alter table" do
    response = alter table(:products) do
      add :name, :string, default: 'Untitled'
      modify :price, :integer, default: 99
      remove :summary
      rename :name, :title
    end

    assert response == {:executed, {:alter, %Table{name: :products},
                        [{:add, :name, :string, [default: 'Untitled']},
                         {:modify, :price, :integer, [default: 99]},
                         {:remove, :summary},
                         {:rename, :name, :title}]}}
  end

  test "references" do
    response = create table(:products) do
      add :category_id, references(:category)
    end

    assert response == {:executed, {:create, %Table{name: :products, key: true},
                        [{:add, :id, :primary_key, []},
                         {:add, :category_id, {:references, :category, :id, :integer}, []}]}}
  end
end
