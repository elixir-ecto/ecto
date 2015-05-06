Code.require_file "../support/mock_repo.exs", __DIR__

defmodule Ecto.MigrationTest do
  # Although this test uses the Ecto.Migration.Runner which
  # is global state, we can run it async as long as this is
  # the only test case that uses the Runner in async mode.
  use ExUnit.Case, async: true

  use Ecto.Migration

  alias Ecto.MockRepo
  alias Ecto.Migration.Table
  alias Ecto.Migration.Index
  alias Ecto.Migration.Reference
  alias Ecto.Migration.Runner

  setup meta do
    {:ok, _} = Runner.start_link(MockRepo, meta[:direction] || :forward, :up, false)

    on_exit fn ->
      try do
        Runner.stop()
      catch
        :exit, _ -> :ok
      end
    end

    :ok
  end

  test "defines __migration__ function" do
    assert function_exported?(__MODULE__, :__migration__, 0)
  end

  test "allows direction to be retrieved" do
    assert direction() == :up
  end

  test "creates a table" do
    assert table(:posts) == %Table{name: :posts, primary_key: true}
    assert table(:posts, primary_key: false) == %Table{name: :posts, primary_key: false}
  end

  test "creates an index" do
    assert index(:posts, [:title]) ==
           %Index{table: :posts, unique: false, name: :posts_title_index, columns: [:title]}
    assert index(:posts, ["lower(title)"]) ==
           %Index{table: :posts, unique: false, name: :posts_lower_title_index, columns: ["lower(title)"]}
    assert index(:posts, [:title], name: :foo, unique: true) ==
           %Index{table: :posts, unique: true, name: :foo, columns: [:title]}
  end

  test "creates a reference" do
    assert references(:posts) ==
           %Reference{table: :posts, column: :id, type: :serial}
    assert references(:posts, type: :uuid, column: :other) ==
           %Reference{table: :posts, column: :other, type: :uuid}
  end

  test "chokes on alias types" do
    assert_raise ArgumentError,
                 ~r"Ecto.DateTime is not a valid database type", fn ->
      add(:hello, Ecto.DateTime)
    end
  end

  ## Forward
  @moduletag direction: :forward

  test "forward: executes the given SQL" do
    execute "HELLO, IS IT ME YOU ARE LOOKING FOR?"
    assert last_command() == "HELLO, IS IT ME YOU ARE LOOKING FOR?"
  end

  test "forward: table exists?" do
    assert exists?(table(:hello))
    assert %Table{name: :hello} = last_exists()
  end

  test "forward: index exists?" do
    assert exists?(index(:hello, [:world]))
    assert %Index{table: :hello} = last_exists()
  end

  test "forward: creates a table" do
    create table = table(:posts) do
      add :title
      add :cost, :decimal, precision: 3
      add :author_id, references(:authors)
      timestamps
    end

    assert last_command() ==
           {:create, table,
              [{:add, :id, :serial, [primary_key: true]},
               {:add, :title, :string, []},
               {:add, :cost, :decimal, [precision: 3]},
               {:add, :author_id, %Reference{table: :authors}, []},
               {:add, :inserted_at, :datetime, [null: false]},
               {:add, :updated_at, :datetime, [null: false]}]}

    create table = table(:posts, primary_key: false, timestamps: false) do
      add :title
    end

    assert last_command() ==
           {:create, table,
              [{:add, :title, :string, []}]}
  end

  test "forward: alters a table" do
    alter table(:posts) do
      add :summary, :text
      modify :title, :text
      remove :views
    end

    assert last_command() ==
           {:alter, %Table{name: :posts},
              [{:add, :summary, :text, []},
               {:modify, :title, :text, []},
               {:remove, :views}]}
  end

  test "forward: drops a table" do
    drop table(:posts)
    assert {:drop, %Table{}} = last_command()
  end

  test "forward: creates an index" do
    create index(:posts, [:title])
    assert {:create, %Index{}} = last_command()
  end

  test "forward: drops an index" do
    drop index(:posts, [:title])
    assert {:drop, %Index{}} = last_command()
  end

  ## Reverse
  @moduletag direction: :backward

  test "backward: fails when executing SQL" do
    assert_raise Ecto.MigrationError, ~r/cannot reverse migration command/, fn ->
      execute "HELLO, IS IT ME YOU ARE LOOKING FOR?"
    end
  end

  test "backward: table exists?" do
    refute exists?(table(:hello))
    assert %Table{name: :hello} = last_exists()
  end

  test "backward: index exists?" do
    refute exists?(index(:hello, [:world]))
    assert %Index{table: :hello} = last_exists()
  end

  test "backward: creates a table" do
    create table(:posts) do
      add :title
      add :cost, :decimal, precision: 3
    end

    assert last_command() ==
           {:drop, %Ecto.Migration.Table{name: :posts, primary_key: true}}
  end

  test "backward: alters a table" do
    alter table(:posts) do
      add :summary, :text
    end

    assert last_command() ==
           {:alter, %Table{name: :posts},
              [{:remove, :summary}]}

    assert_raise Ecto.MigrationError, ~r/cannot reverse migration command/, fn ->
      alter table(:posts) do
        remove :summary
      end
    end
  end

  test "backward: drops a table" do
    assert_raise Ecto.MigrationError, ~r/cannot reverse migration command/, fn ->
      drop table(:posts)
    end
  end

  test "backward: creates an index" do
    create index(:posts, [:title])
    assert {:drop, %Index{}} = last_command()
  end

  test "backward: creates an index (does not exist)" do
    Process.put(:ddl_exists, false)
    create index(:posts, [:title])
    assert last_exists()
    refute last_command()
  end

  test "backward: drops an index" do
    drop index(:posts, [:title])
    assert {:create, %Index{}} = last_command()
  end

  defp last_exists(), do: Process.get(:last_exists)
  defp last_command(), do: Process.get(:last_command)
end
