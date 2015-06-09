defmodule Ecto.Integration.AlterTableTest do
  use ExUnit.Case

  require Ecto.Integration.TestRepo, as: TestRepo

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
