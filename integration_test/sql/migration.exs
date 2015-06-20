defmodule Ecto.Integration.MigrationTest do
  use ExUnit.Case

  require Ecto.Integration.TestRepo, as: TestRepo

  defmodule CreateMigration do
    use Ecto.Migration

    @table table(:create_table_migration)
    @index index(:create_table_migration, [:value], unique: true)

    def up do
      assert false == exists? @table
      create @table do
        add :value, :integer
      end
      create @index
      assert true == exists? @table
    end

    def down do
      drop @index
      drop @table
      assert false == exists? @table
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
      drop table(:add_col_migration)
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
      drop table(:alter_col_migration)
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
      drop table(:drop_col_migration)
    end
  end

  import Ecto.Query, only: [from: 2]
  import Ecto.Migrator, only: [up: 4, down: 4]

  test "create and drop table and indexes" do
    assert :ok == up(TestRepo, 20050906120000, CreateMigration, log: false)
  after
    assert :ok == down(TestRepo, 20050906120000, CreateMigration, log: false)
  end

  @tag :add_column
  test "add column" do
    assert :ok == up(TestRepo, 20070906120000, AddColumnMigration, log: false)
    assert 2 == TestRepo.one from p in "add_col_migration", select: p.to_be_added
  after
    :ok = down(TestRepo, 20070906120000, AddColumnMigration, log: false)
  end

  @tag :modify_column
  test "modify column" do
    assert :ok == up(TestRepo, 20080906120000, AlterColumnMigration, log: false)
    assert "foo" == TestRepo.one from p in "alter_col_migration", select: p.to_be_modified
  after
    :ok = down(TestRepo, 20080906120000, AlterColumnMigration, log: false)
  end

  @tag :remove_column
  test "remove column" do
    assert :ok == up(TestRepo, 20090906120000, DropColumnMigration, log: false)
    assert catch_error(TestRepo.one from p in "drop_col_migration", select: p.to_be_removed)
  after
    :ok = down(TestRepo, 20090906120000, DropColumnMigration, log: false)
  end
end
