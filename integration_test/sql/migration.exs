Code.require_file "../../test/support/file_helpers.exs", __DIR__

defmodule Ecto.Integration.MigratorTest do
  use Ecto.Integration.Case

  import Support.FileHelpers
  import Ecto.Migrator, only: [migrated_versions: 1]
  require Ecto.Integration.TestRepo, as: TestRepo

  defmodule GoodMigration do
    use Ecto.Migration

    def up do
      :ok
    end

    def down do
      :ok
    end
  end

  defmodule BadMigration do
    use Ecto.Migration

    def change do
      execute "CREATE WHAT"
    end
  end

  import Ecto.Migrator

  test "schema migration" do
    [migration] = TestRepo.all(Ecto.Migration.SchemaMigration)
    assert migration.version == 0
    assert migration.inserted_at
  end

  test "migrations up and down" do
    assert migrated_versions(TestRepo) == [0]
    assert up(TestRepo, 20080906120000, GoodMigration, log: false) == :ok

    assert migrated_versions(TestRepo) == [0, 20080906120000]
    assert up(TestRepo, 20080906120000, GoodMigration, log: false) == :already_up
    assert migrated_versions(TestRepo) == [0, 20080906120000]
    assert down(TestRepo, 20080906120001, GoodMigration, log: false) == :already_down
    assert migrated_versions(TestRepo) == [0, 20080906120000]
    assert down(TestRepo, 20080906120000, GoodMigration, log: false) == :ok
    assert migrated_versions(TestRepo) == [0]
  end

  test "bad migration" do
    assert catch_error(up(TestRepo, 20080906120000, BadMigration, log: false))
  end

  test "run up to/step migration" do
    in_tmp fn path ->
      create_migration(47)
      create_migration(48)

      assert [47] = run(TestRepo, path, :up, step: 1, log: false)
      assert count_entries() == 1

      assert [48] = run(TestRepo, path, :up, to: 48, log: false)
    end
  end

  test "run down to/step migration" do
    in_tmp fn path ->
      migrations = [
        create_migration(49),
        create_migration(50),
      ]

      assert [49, 50] = run(TestRepo, path, :up, all: true, log: false)
      purge migrations

      assert [50] = run(TestRepo, path, :down, step: 1, log: false)
      purge migrations

      assert count_entries() == 1
      assert [50] = run(TestRepo, path, :up, to: 50, log: false)
    end
  end

  test "runs all migrations" do
    in_tmp fn path ->
      migrations = [
        create_migration(53),
        create_migration(54),
      ]

      assert [53, 54] = run(TestRepo, path, :up, all: true, log: false)
      assert [] = run(TestRepo, path, :up, all: true, log: false)
      purge migrations

      assert [54, 53] = run(TestRepo, path, :down, all: true, log: false)
      purge migrations

      assert count_entries() == 0
      assert [53, 54] = run(TestRepo, path, :up, all: true, log: false)
    end
  end

  defp count_entries() do
    import Ecto.Query, only: [from: 2]
    TestRepo.one! from p in "barebones", select: count(1)
  end

  defp create_migration(num) do
    module = Module.concat(__MODULE__, "Migration#{num}")

    File.write! "#{num}_migration_#{num}.exs", """
    defmodule #{module} do
      use Ecto.Migration

      def up do
        execute "INSERT INTO barebones (num) VALUES (#{num})"
      end

      def down do
        execute "DELETE FROM barebones WHERE num = #{num}"
      end
    end
    """

    module
  end

  defp purge(modules) do
    Enum.each(List.wrap(modules), fn m ->
      :code.delete m
      :code.purge m
    end)
  end
end

defmodule Ecto.Integration.MigrationTest do
  use ExUnit.Case

  require Ecto.Integration.TestRepo, as: TestRepo

  defmodule CreateTableMigration do
    use Ecto.Migration

    @table table(:create_table_migration)

    def up do
      assert false == exists? @table
      create @table do
        add :value, :integer
      end
      assert true == exists? @table
    end

    def down do
      drop @table
      assert false == exists? @table
    end
  end

  defmodule CreateIndexMigration do
    use Ecto.Migration

    @index index(:users, [:custom_id], unique: true)

    def up do
      assert false == exists? @index
      create @index
      assert true == exists? @index
    end

    def down do
      drop @index
      assert false == exists? @index
    end
  end

  defmodule AddColumnModel do
    use Ecto.Model

    schema "add_col_migration" do
      field :value, :integer
      field :to_be_added, :integer
    end
  end

  defmodule AddColumnMigration do
    use Ecto.Migration

    def up do
      create table(:add_col_migration) do
        add :value, :integer
      end

      alter table(:add_col_migration) do
        add :to_be_added, :integer
      end

      execute "INSERT INTO add_col_migration (value, to_be_added) VALUES (1, 2)"
    end

    def down do
      :ok
    end
  end

  defmodule AlterColumnModel do
    use Ecto.Model

    schema "alter_col_migration" do
      field :to_be_modified, :string
    end
  end

  defmodule AlterColumnMigration do
    use Ecto.Migration

    def up do
      create table(:alter_col_migration) do
        add :to_be_modified, :integer
      end

      alter table(:alter_col_migration) do
        modify :to_be_modified, :string
      end

      execute "INSERT INTO alter_col_migration (to_be_modified) VALUES ('foo')"
    end

    def down do
      :ok
    end
  end

  defmodule DropColumnModel do
    use Ecto.Model

    schema "drop_col_migration" do
      field :value, :integer
      field :to_be_removed, :integer
    end
  end

  defmodule DropColumnMigration do
    use Ecto.Migration

    def up do
      create table(:drop_col_migration) do
        add :value, :integer
        add :to_be_removed, :integer
      end

      execute "INSERT INTO drop_col_migration (value, to_be_removed) VALUES (1, 2)"

      alter table(:drop_col_migration) do
        remove :to_be_removed
      end
    end

    def down do
      :ok
    end
  end

  import Ecto.Query, only: [from: 2]
  import Ecto.Migrator, only: [up: 4, down: 4]
  import Ecto.Migration, only: [exists?: 1, table: 1, index: 3]

  test "create and drop table" do
    assert :ok == up(TestRepo, 20050906120000, CreateTableMigration, log: false)
    assert :ok == down(TestRepo, 20050906120000, CreateTableMigration, log: false)
  end

  test "create and drop index" do
    assert :ok == up(TestRepo, 20060906120000, CreateIndexMigration, log: false)
    assert :ok == down(TestRepo, 20060906120000, CreateIndexMigration, log: false)
  end

  @tag :add_column
  test "add column" do
    assert :ok == up(TestRepo, 20070906120000, AddColumnMigration, log: false)
    assert 2 == TestRepo.one from p in AddColumnModel, select: p.to_be_added
    :ok = down(TestRepo, 20070906120000, AddColumnMigration, log: false)
  end

  @tag :modify_column
  test "modify column" do
    assert :ok == up(TestRepo, 20080906120000, AlterColumnMigration, log: false)
    assert "foo" == TestRepo.one from p in AlterColumnModel, select: p.to_be_modified
    :ok = down(TestRepo, 20080906120000, AlterColumnMigration, log: false)
  end

  @tag :remove_column
  test "remove column" do
    assert :ok == up(TestRepo, 20090906120000, DropColumnMigration, log: false)
    assert catch_error(TestRepo.one from p in DropColumnModel, select: p.to_be_removed)
    :ok = down(TestRepo, 20090906120000, DropColumnMigration, log: false)
  end
end
