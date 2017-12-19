defmodule Ecto.MigrationTest do
  # Although this test uses the Ecto.Migration.Runner which
  # is global state, we can run it async as long as this is
  # the only test case that uses the Runner in async mode.
  use ExUnit.Case, async: true

  use Ecto.Migration

  alias Ecto.TestRepo
  alias Ecto.Migration.{Table, Index, Reference, Constraint}
  alias Ecto.Migration.Runner

  setup meta do
    config = Application.get_env(:ecto, TestRepo, [])
    Application.put_env(:ecto, TestRepo, Keyword.merge(config, meta[:repo_config] || []))
    on_exit fn -> Application.put_env(:ecto, TestRepo, config) end
  end

  setup meta do
    direction = meta[:direction] || :forward
    {:ok, runner} = Runner.start_link(self(), TestRepo, direction, :up, %{level: false, sql: false})
    Runner.metadata(runner, meta)
    {:ok, runner: runner}
  end

  test "defines __migration__ function" do
    assert function_exported?(__MODULE__, :__migration__, 0)
  end

  test "allows direction to be retrieved" do
    assert direction() == :up
  end

  @tag prefix: "foo"
  test "allows prefix to be retrieved" do
    assert prefix() == "foo"
  end

  test "creates a table" do
    assert table(:posts) == %Table{name: "posts", primary_key: true}
    assert table("posts") == %Table{name: "posts", primary_key: true}
    assert table(:posts, primary_key: false) == %Table{name: "posts", primary_key: false}
    assert table(:posts, prefix: "foo") == %Table{name: "posts", primary_key: true, prefix: "foo"}
  end

  test "creates an index" do
    assert index(:posts, [:title]) ==
           %Index{table: "posts", unique: false, name: :posts_title_index, columns: [:title]}
    assert index("posts", [:title]) ==
           %Index{table: "posts", unique: false, name: :posts_title_index, columns: [:title]}
    assert index(:posts, :title) ==
           %Index{table: "posts", unique: false, name: :posts_title_index, columns: [:title]}
    assert index(:posts, ["lower(title)"]) ==
           %Index{table: "posts", unique: false, name: :posts_lower_title_index, columns: ["lower(title)"]}
    assert index(:posts, [:title], name: :foo, unique: true) ==
           %Index{table: "posts", unique: true, name: :foo, columns: [:title]}
    assert unique_index(:posts, [:title], name: :foo) ==
           %Index{table: "posts", unique: true, name: :foo, columns: [:title]}
    assert unique_index(:posts, :title, name: :foo) ==
           %Index{table: "posts", unique: true, name: :foo, columns: [:title]}
    assert unique_index(:table_one__table_two, :title) ==
           %Index{table: "table_one__table_two", unique: true, name: :table_one__table_two_title_index, columns: [:title]}
  end

  test "creates a reference" do
    assert references(:posts) ==
           %Reference{table: "posts", column: :id, type: :bigserial}
    assert references("posts") ==
           %Reference{table: "posts", column: :id, type: :bigserial}
    assert references(:posts, type: :uuid, column: :other) ==
           %Reference{table: "posts", column: :other, type: :uuid}
  end

  test "creates a constraint" do
    assert constraint(:posts, :price_is_positive, check: "price > 0") ==
           %Constraint{table: "posts", name: :price_is_positive, check: "price > 0"}
    assert constraint("posts", :price_is_positive, check: "price > 0") ==
           %Constraint{table: "posts", name: :price_is_positive, check: "price > 0"}
    assert constraint(:posts, :exclude_price, exclude: "price") ==
           %Constraint{table: "posts", name: :exclude_price, exclude: "price"}
    assert constraint("posts", :exclude_price, exclude: "price") ==
           %Constraint{table: "posts", name: :exclude_price, exclude: "price"}
  end

  test "runs a reversible command" do
    assert execute("SELECT 1", "SELECT 2") == :ok
  end

  test "chokes on alias types" do
    assert_raise ArgumentError, ~r"Ecto.DateTime is not a valid database type", fn ->
      add(:hello, Ecto.DateTime)
    end
  end

  test "flush clears out commands", %{runner: runner} do
    execute "TEST"
    commands = Agent.get(runner, & &1.commands)
    assert commands == ["TEST"]
    flush()
    commands = Agent.get(runner, & &1.commands)
    assert commands == []
  end

  ## Forward
  @moduletag direction: :forward

  test "forward: executes the given SQL" do
    execute "HELLO, IS IT ME YOU ARE LOOKING FOR?"
    flush()
    assert last_command() == "HELLO, IS IT ME YOU ARE LOOKING FOR?"
  end

  test "forward: executes given keyword command" do
    execute create: "posts", capped: true, size: 1024
    flush()
    assert last_command() == [create: "posts", capped: true, size: 1024]
  end

  test "forward: creates a table" do
    result = create(table = table(:posts)) do
      add :title, :string
      add :cost, :decimal, precision: 3
      add :likes, :"int UNSIGNED", default: 0
      add :author_id, references(:authors)
      timestamps()
    end
    flush()

    assert last_command() ==
           {:create, table,
              [{:add, :id, :bigserial, [primary_key: true]},
               {:add, :title, :string, []},
               {:add, :cost, :decimal, [precision: 3]},
               {:add, :likes, :"int UNSIGNED", [default: 0]},
               {:add, :author_id, %Reference{table: "authors"}, []},
               {:add, :inserted_at, :naive_datetime, [null: false]},
               {:add, :updated_at, :naive_datetime, [null: false]}]}

    assert result == table(:posts)

    create table = table(:posts, primary_key: false, timestamps: false) do
      add :title, :string
    end
    flush()

    assert last_command() ==
           {:create, table,
              [{:add, :title, :string, []}]}
  end

  @tag repo_config: [migration_primary_key: [name: :uuid, type: :uuid]]
  test "forward: create a table with custom primary key" do
    create(table = table(:posts)) do
    end
    flush()

    assert last_command() ==
           {:create, table, [{:add, :uuid, :uuid, [primary_key: true]}]}
  end

  @tag repo_config: [migration_primary_key: [type: :uuid, default: {:fragment, "gen_random_uuid()"}]]
  test "forward: create a table with custom primary key options" do
    create(table = table(:posts)) do
    end
    flush()

    assert last_command() ==
           {:create, table, [{:add, :id, :uuid, [primary_key: true, default: {:fragment, "gen_random_uuid()"}]}]}
  end

  @tag repo_config: [migration_timestamps: [type: :utc_datetime, null: true]]
  test "forward: create a table with timestamps" do
    create(table = table(:posts)) do
      timestamps()
    end
    flush()

    assert last_command() ==
           {:create, table, [
              {:add, :id, :bigserial, [primary_key: true]},
              {:add, :inserted_at, :utc_datetime, [null: true]},
              {:add, :updated_at, :utc_datetime, [null: true]}]}
  end

  test "forward: creates a table without precision option for numeric type" do
    assert_raise ArgumentError, "column cost is missing precision option", fn ->
      create(table(:posts)) do
        add :title, :string
        add :cost, :decimal, scale: 3
        timestamps()
      end
      flush()
    end
  end

  test "forward: creates a table without updated_at timestamp" do
    create table = table(:posts, primary_key: false) do
      timestamps(inserted_at: :created_at, updated_at: false)
    end
    flush()

    assert last_command() ==
           {:create, table,
              [{:add, :created_at, :naive_datetime, [null: false]}]}
  end

  test "forward: creates a table with timestamps of type date" do
    create table = table(:posts, primary_key: false) do
      timestamps(inserted_at: :inserted_on, updated_at: :updated_on, type: :date)
    end
    flush()

    assert last_command() ==
           {:create, table,
              [{:add, :inserted_on, :date, [null: false]},
               {:add, :updated_on, :date, [null: false]}]}
  end

  test "forward: creates a table with timestamps of database specific type" do
    create table = table(:posts, primary_key: false) do
      timestamps(type: :"datetime(6)")
    end
    flush()

    assert last_command() ==
           {:create, table,
              [{:add, :inserted_at, :"datetime(6)", [null: false]},
               {:add, :updated_at, :"datetime(6)", [null: false]}]}
  end

  test "forward: creates an empty table" do
    create table = table(:posts)
    flush()

    assert last_command() ==
           {:create, table, [{:add, :id, :bigserial, [primary_key: true]}]}
  end

  test "forward: alters a table" do
    alter table(:posts) do
      add :summary, :text
      modify :title, :text
      remove :views
    end
    flush()

    assert last_command() ==
           {:alter, %Table{name: "posts"},
              [{:add, :summary, :text, []},
               {:modify, :title, :text, []},
               {:remove, :views}]}
  end

  test "forward: alter numeric column without specifying precision" do
    assert_raise ArgumentError, "column cost is missing precision option", fn ->
      alter table(:posts) do
        modify :cost, :decimal, scale: 5
      end
      flush()
    end
  end

  test "forward: rename column" do
    result = rename(table(:posts), :given_name, to: :first_name)
    flush()

    assert last_command() == {:rename, %Table{name: "posts"}, :given_name, :first_name}
    assert result == table(:posts)
  end

  test "forward: drops a table" do
    result = drop table(:posts)
    flush()
    assert {:drop, %Table{}} = last_command()
    assert result == table(:posts)
  end

  test "forward: creates an index" do
    create index(:posts, [:title])
    flush()
    assert {:create, %Index{}} = last_command()
  end

  test "forward: creates a check constraint" do
    create constraint(:posts, :price, check: "price > 0")
    flush()
    assert {:create, %Constraint{}} = last_command()
  end

  test "forward: creates an exclusion constraint" do
    create constraint(:posts, :price, exclude: "price")
    flush()
    assert {:create, %Constraint{}} = last_command()
  end

  test "forward: raises on invalid constraints" do
    assert_raise ArgumentError, "a constraint must have either a check or exclude option", fn ->
      create constraint(:posts, :price)
      flush()
    end

    assert_raise ArgumentError, "a constraint must not have both check and exclude options", fn ->
      create constraint(:posts, :price, check: "price > 0", exclude: "price")
      flush()
    end
  end

  test "forward: drops an index" do
    drop index(:posts, [:title])
    flush()
    assert {:drop, %Index{}} = last_command()
  end

  test "forward: drops a constraint" do
    drop constraint(:posts, :price)
    flush()
    assert {:drop, %Constraint{}} = last_command()
  end

  test "forward: renames a table" do
    result = rename(table(:posts), to: table(:new_posts))
    flush()
    assert {:rename, %Table{name: "posts"}, %Table{name: "new_posts"}} = last_command()
    assert result == table(:new_posts)
  end

  # prefix

  test "forward: creates a table with prefix from migration" do
    create(table(:posts, prefix: "foo"))
    flush()

    {_, table, _} = last_command()
    assert table.prefix == "foo"
  end

  @tag prefix: "foo"
  test "forward: creates a table with prefix from manager" do
    create(table(:posts))
    flush()

    {_, table, _} = last_command()
    assert table.prefix == "foo"
  end

  @tag prefix: "foo", repo_config: [migration_default_prefix: "baz"]
  test "forward: creates a table with prefix from manager overriding the default prefix configuration" do
    create(table(:posts))
    flush()

    {_, table, _} = last_command()
    assert table.prefix == "foo"
  end

  @tag repo_config: [migration_default_prefix: "baz"]
  test "forward: creates a table with prefix from migration overriding the default prefix configuration" do
    create(table(:posts, prefix: "foo"))
    flush()

    {_, table, _} = last_command()
    assert table.prefix == "foo"
  end  

  @tag repo_config: [migration_default_prefix: "baz"]
  test "forward: create a table with prefix from configuration" do
    create(table(:posts))
    flush()

    {_, table, _} = last_command()
    assert table.prefix == "baz"
  end

  @tag prefix: :foo
  test "forward: creates a table with prefix from manager matching atom prefix" do
    create(table(:posts, prefix: "foo"))
    flush()

    {_, table, _} = last_command()
    assert table.prefix == "foo"
  end

  @tag prefix: "foo"
  test "forward: creates a table with prefix from manager matching string prefix" do
    create(table(:posts, prefix: :foo))
    flush()

    {_, table, _} = last_command()
    assert table.prefix == :foo
  end

  @tag prefix: :bar
  test "forward: raise error when prefixes don't match" do
    assert_raise Ecto.MigrationError,
                 "the :prefix option `foo` does match the migrator prefix `bar`", fn ->
      create(table(:posts, prefix: "foo"))
      flush()
    end
  end

  test "forward: drops a table with prefix from migration" do
    drop(table(:posts, prefix: "foo"))
    flush()
    {:drop, table} = last_command()
    assert table.prefix == "foo"
  end

  @tag prefix: "foo"
  test "forward: drops a table with prefix from manager" do
    drop(table(:posts))
    flush()
    {:drop, table} = last_command()
    assert table.prefix == "foo"
  end

  @tag repo_config: [migration_default_prefix: "baz"]
  test "forward: drops a table with prefix from configuration" do
    drop(table(:posts))
    flush()
    {:drop, table} = last_command()
    assert table.prefix == "baz"
  end

  test "forward: rename column on table with index prefixed from migration" do
    rename(table(:posts, prefix: "foo"), :given_name, to: :first_name)
    flush()

    {_, table, _, new_name} = last_command()
    assert table.prefix == "foo"
    assert new_name == :first_name
  end

  @tag prefix: "foo"
  test "forward: rename column on table with index prefixed from manager" do
    rename(table(:posts), :given_name, to: :first_name)
    flush()

    {_, table, _, new_name} = last_command()
    assert table.prefix == "foo"
    assert new_name == :first_name
  end

  @tag repo_config: [migration_default_prefix: "baz"]
  test "forward: rename column on table with index prefixed from configuration" do
    rename(table(:posts), :given_name, to: :first_name)
    flush()

    {_, table, _, new_name} = last_command()
    assert table.prefix == "baz"
    assert new_name == :first_name
  end

  test "forward: creates an index with prefix from migration" do
    create index(:posts, [:title], prefix: "foo")
    flush()
    {_, index} = last_command()
    assert index.prefix == "foo"
  end

  @tag prefix: "foo"
  test "forward: creates an index with prefix from manager" do
    create index(:posts, [:title])
    flush()
    {_, index} = last_command()
    assert index.prefix == "foo"
  end

  @tag repo_config: [migration_default_prefix: "baz"]
  test "forward: creates an index with prefix from configuration" do
    create index(:posts, [:title])
    flush()
    {_, index} = last_command()
    assert index.prefix == "baz"
  end

  test "forward: drops an index with a prefix from migration" do
    drop index(:posts, [:title], prefix: "foo")
    flush()
    {_, index} = last_command()
    assert index.prefix == "foo"
  end

  @tag prefix: "foo"
  test "forward: drops an index with a prefix from manager" do
    drop index(:posts, [:title])
    flush()
    {_, index} = last_command()
    assert index.prefix == "foo"
  end

  @tag repo_config: [migration_default_prefix: "baz"]
  test "forward: drops an index with a prefix from configuration" do
    drop index(:posts, [:title])
    flush()
    {_, index} = last_command()
    assert index.prefix == "baz"
  end

  test "forward: executes a command" do
    execute "SELECT 1", "SELECT 2"
    flush()
    assert "SELECT 1" = last_command()
  end

  test "fails gracefully with nested create" do
    assert_raise Ecto.MigrationError, "cannot execute nested commands", fn ->
      create table(:posts) do
        create index(:posts, [:foo])
      end
      flush()
    end

    assert_raise Ecto.MigrationError, "cannot execute nested commands", fn ->
      create table(:posts) do
        create table(:foo) do
        end
      end
      flush()
    end
  end

  ## Reverse
  @moduletag direction: :backward

  test "backward: fails when executing SQL" do
    assert_raise Ecto.MigrationError, ~r/cannot reverse migration command/, fn ->
      execute "HELLO, IS IT ME YOU ARE LOOKING FOR?"
      flush()
    end
  end

  test "backward: creates a table" do
    create table = table(:posts) do
      add :title, :string
      add :cost, :decimal, precision: 3
    end
    flush()

    assert last_command() == {:drop, table}
  end

  test "backward: creates an empty table" do
    create table = table(:posts)
    flush()

    assert last_command() == {:drop, table}
  end

  test "backward: alters a table" do
    alter table(:posts) do
      add :summary, :text
      add :extension, :text
    end
    flush()

    assert last_command() ==
           {:alter, %Table{name: "posts"},
              [{:remove, :extension}, {:remove, :summary}]}

    assert_raise Ecto.MigrationError, ~r/cannot reverse migration command/, fn ->
      alter table(:posts) do
        add :summary, :text
        remove :summary
      end
      flush()
    end
  end

  test "backward: rename column" do
    rename table(:posts), :given_name, to: :first_name
    flush()

    assert last_command() == {:rename, %Table{name: "posts"}, :first_name, :given_name}
  end

  test "backward: drops a table" do
    assert_raise Ecto.MigrationError, ~r/cannot reverse migration command/, fn ->
      drop table(:posts)
      flush()
    end
  end

  test "backward: creates an index" do
    create index(:posts, [:title])
    flush()
    assert {:drop, %Index{}} = last_command()
  end

  test "backward: drops an index" do
    drop index(:posts, [:title])
    flush()
    assert {:create, %Index{}} = last_command()
  end

  test "backward: renames a table" do
    rename table(:posts), to: table(:new_posts)
    flush()
    assert {:rename, %Table{name: "new_posts"}, %Table{name: "posts"}} = last_command()
  end

  test "backward: reverses a command" do
    execute "SELECT 1", "SELECT 2"
    flush()
    assert "SELECT 2" = last_command()
  end

  test "references foreign keys types must be the same as primary defaults" do
    %{runner: runner} = Process.get(:ecto_migration)
    Agent.update(runner, fn state ->
      config = Keyword.put(state.config, :migration_primary_key, [type: :binary_id])
      Map.put(state, :config, config)
    end)

    assert references(:posts) ==
           %Reference{table: "posts", column: :id, type: :binary_id}
  end

  defp last_command(), do: Process.get(:last_command)
end
