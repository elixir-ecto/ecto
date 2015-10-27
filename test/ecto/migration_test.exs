defmodule Ecto.MigrationTest do
  # Although this test uses the Ecto.Migration.Runner which
  # is global state, we can run it async as long as this is
  # the only test case that uses the Runner in async mode.
  use ExUnit.Case, async: true

  use Ecto.Migration

  alias Ecto.TestRepo
  alias Ecto.Migration.Table
  alias Ecto.Migration.Index
  alias Ecto.Migration.Reference
  alias Ecto.Migration.Runner
  alias Ecto.Migration.Manager

  setup meta do
    
    Runner.start_link(TestRepo, meta[:direction] || :forward, :up, false, nil)
    :ok
  end

  test "defines __migration__ function" do
    assert function_exported?(__MODULE__, :__migration__, 0)
    Runner.stop()
  end

  test "allows direction to be retrieved" do
    assert direction() == :up
    Runner.stop()
  end

  test "creates a table" do
    assert table(:posts) == %Table{name: :posts, primary_key: true}
    assert table(:posts, primary_key: false) == %Table{name: :posts, primary_key: false}
    assert table(:posts, prefix: :foo) == %Table{name: :posts, primary_key: true, prefix: :foo}
    Runner.stop()
  end

  test "creates an index" do
    assert index(:posts, [:title]) ==
           %Index{table: :posts, unique: false, name: :posts_title_index, columns: [:title]}
    assert index(:posts, ["lower(title)"]) ==
           %Index{table: :posts, unique: false, name: :posts_lower_title_index, columns: ["lower(title)"]}
    assert index(:posts, [:title], name: :foo, unique: true) ==
           %Index{table: :posts, unique: true, name: :foo, columns: [:title]}
    assert unique_index(:posts, [:title], name: :foo) ==
           %Index{table: :posts, unique: true, name: :foo, columns: [:title]}
    Runner.stop()
  end

  test "creates a reference" do
    assert references(:posts) ==
           %Reference{table: :posts, column: :id, type: :serial}
    assert references(:posts, type: :uuid, column: :other) ==
           %Reference{table: :posts, column: :other, type: :uuid}
    Runner.stop()
  end

  test "chokes on alias types" do
    assert_raise ArgumentError,
                 ~r"Ecto.DateTime is not a valid database type", fn ->
      add(:hello, Ecto.DateTime)
    end
    Runner.stop()
  end

  test "flush clears out commands" do
    execute "TEST"
    commands = Agent.get(runner, & &1.commands)
    assert commands == ["TEST"]
    flush
    commands = Agent.get(runner, & &1.commands)
    assert commands == []
    Runner.stop()
  end

  ## Forward
  @moduletag direction: :forward

  test "forward: executes the given SQL" do
    execute "HELLO, IS IT ME YOU ARE LOOKING FOR?"
    flush
    assert last_command() == "HELLO, IS IT ME YOU ARE LOOKING FOR?"
    Runner.stop()
  end

  test "forward: executes given keyword command" do
    execute create: "posts", capped: true, size: 1024
    flush
    assert last_command() == [create: "posts", capped: true, size: 1024]
    Runner.stop()
  end

  test "forward: creates a table" do
    result = create(table = table(:posts)) do
      add :title, :string
      add :cost, :decimal, precision: 3
      add :author_id, references(:authors)
      timestamps
    end
    flush

    assert last_command() ==
           {:create, table,
              [{:add, :id, :serial, [primary_key: true]},
               {:add, :title, :string, []},
               {:add, :cost, :decimal, [precision: 3]},
               {:add, :author_id, %Reference{table: :authors}, []},
               {:add, :inserted_at, :datetime, [null: false]},
               {:add, :updated_at, :datetime, [null: false]}]}

    assert result == table(:posts)

    create table = table(:posts, primary_key: false, timestamps: false) do
      add :title, :string
    end
    flush

    assert last_command() ==
           {:create, table,
              [{:add, :title, :string, []}]}
    Runner.stop()
  end

  test "forward: creates an empty table" do
    create table = table(:posts)
    flush

    assert last_command() ==
           {:create, table, [{:add, :id, :serial, [primary_key: true]}]}
    Runner.stop()
  end

  test "forward: alters a table" do
    alter table(:posts) do
      add :summary, :text
      modify :title, :text
      remove :views
    end
    flush

    assert last_command() ==
           {:alter, %Table{name: :posts},
              [{:add, :summary, :text, []},
               {:modify, :title, :text, []},
               {:remove, :views}]}
    Runner.stop()
  end

  test "forward: rename column" do
    result = rename(table(:posts), :given_name, to: :first_name)
    flush

    assert last_command() == {:rename, %Table{name: :posts}, :given_name, :first_name}
    assert result == table(:posts)
    Runner.stop()
  end

  test "forward: drops a table" do
    result = drop table(:posts)
    flush
    assert {:drop, %Table{}} = last_command()
    assert result == table(:posts)
    Runner.stop()
  end

  test "forward: creates an index" do
    create index(:posts, [:title])
    flush
    assert {:create, %Index{}} = last_command()
    Runner.stop()
  end

  test "forward: drops an index" do
    drop index(:posts, [:title])
    flush
    assert {:drop, %Index{}} = last_command()
    Runner.stop()
  end

  test "forward: renames a table" do
    result = rename(table(:posts), to: table(:new_posts))
    flush
    assert {:rename, %Table{name: :posts}, %Table{name: :new_posts}} = last_command()
    assert result == table(:new_posts)
    Runner.stop()
  end

  #prefix

  test "forward: creates a table with prefix from migration" do
    create(table(:posts, prefix: :foo))
    flush

    {_, table, _} = last_command()

    assert table.prefix == :foo
    Runner.stop()
  end

  test "forward: creates a table with prefix from manager" do
    Runner.stop()
    Runner.start_link(TestRepo, :forward, :up, false, :foo)

    create(table(:posts))
    flush

    {_, table, _} = last_command()

    assert table.prefix == :foo
    Runner.stop()
  end

  test "forward: creates a table with prefix from manager matching prefix from migration" do
    Runner.stop()
    Runner.start_link(TestRepo, :forward, :up, false, :foo)

    create(table(:posts, prefix: :foo))
    flush

    {_, table, _} = last_command()

    assert table.prefix == :foo
    Runner.stop()
  end

  test "forward: raise error when prefixes don't match" do
    Runner.stop()
    Runner.start_link(TestRepo, :forward, :up, false, :bar)

    assert_raise Ecto.MigrationError, ~r/prefixes given as migration options must match global migrator prefix/, fn ->
      create(table(:posts, prefix: :foo))
      flush
    end
    Runner.stop()
  end

  test "forward: drops a table with prefix from migration" do
    drop(table(:posts, prefix: :foo))
    flush
    {:drop, table} = last_command()
    assert table.prefix == :foo
    Runner.stop()
  end

  test "forward: drops a table with prefix from manager" do
    Runner.stop()
    Runner.start_link(TestRepo, :forward, :up, false, :foo)

    drop(table(:posts))
    flush
    {:drop, table} = last_command()
    assert table.prefix == :foo
    Runner.stop()
  end

  test "forward: rename column on table with index prefixed from migration" do
    rename(table(:posts, prefix: :foo), :given_name, to: :first_name)
    flush

    {_, table, _, new_name} = last_command()
    assert table.prefix == :foo
    assert new_name == :first_name
    Runner.stop()
  end

  test "forward: rename column on table with index prefixed from manager" do
    Runner.stop()
    Runner.start_link(TestRepo, :forward, :up, false, :foo)

    rename(table(:posts), :given_name, to: :first_name)
    flush

    {_, table, _, new_name} = last_command()
    assert table.prefix == :foo
    assert new_name == :first_name
    Runner.stop()
  end

  test "forward: creates an index with prefix from migration" do
    create index(:posts, [:title], prefix: :foo)
    flush
    {_, index} = last_command()
    assert index.prefix == :foo
    Runner.stop()
  end

  test "forward: creates an index with prefix from manager" do
    Runner.stop()
    Runner.start_link(TestRepo, :forward, :up, false, :foo)

    create index(:posts, [:title])
    flush
    {_, index} = last_command()
    assert index.prefix == :foo
    Runner.stop()
  end

  test "forward: drops an index with a prefix from migration" do
    drop index(:posts, [:title], prefix: :foo)
    flush
    {_, index} = last_command()
    assert index.prefix == :foo
    Runner.stop()
  end

  test "forward: drops an index with a prefix from manager" do
    Runner.stop()
    Runner.start_link(TestRepo, :forward, :up, false, :foo)

    drop index(:posts, [:title])
    flush
    {_, index} = last_command()
    assert index.prefix == :foo
    Runner.stop()
  end

  ## Reverse
  @moduletag direction: :backward

  test "backward: fails when executing SQL" do
    assert_raise Ecto.MigrationError, ~r/cannot reverse migration command/, fn ->
      execute "HELLO, IS IT ME YOU ARE LOOKING FOR?"
      flush
    end
    Runner.stop()
  end

  test "backward: creates a table" do
    create table = table(:posts) do
      add :title, :string
      add :cost, :decimal, precision: 3
    end
    flush

    assert last_command() == {:drop, table}
    Runner.stop()
  end

  test "backward: creates an empty table" do
    create table = table(:posts)
    flush

    assert last_command() == {:drop, table}
    Runner.stop()
  end

  test "backward: alters a table" do
    alter table(:posts) do
      add :summary, :text
    end
    flush

    assert last_command() ==
           {:alter, %Table{name: :posts},
              [{:remove, :summary}]}

    assert_raise Ecto.MigrationError, ~r/cannot reverse migration command/, fn ->
      alter table(:posts) do
        remove :summary
      end
      flush
    end
    Runner.stop()
  end

  test "backward: rename column" do
    rename table(:posts), :given_name, to: :first_name
    flush

    assert last_command() == {:rename, %Table{name: :posts}, :first_name, :given_name}
    Runner.stop()
  end

  test "backward: drops a table" do
    assert_raise Ecto.MigrationError, ~r/cannot reverse migration command/, fn ->
      drop table(:posts)
      flush
    end
    Runner.stop()
  end

  test "backward: creates an index" do
    create index(:posts, [:title])
    flush
    assert {:drop_if_exists, %Index{}} = last_command()
    Runner.stop()
  end

  test "backward: drops an index" do
    drop index(:posts, [:title])
    flush
    assert {:create, %Index{}} = last_command()
    Runner.stop()
  end

  test "backward: renames a table" do
    rename table(:posts), to: table(:new_posts)
    flush
    assert {:rename, %Table{name: :new_posts}, %Table{name: :posts}} = last_command()
    Runner.stop()
  end

  defp last_command(), do: Process.get(:last_command)

  defp runner do
    Manager.get_runner(self())
  end
end
