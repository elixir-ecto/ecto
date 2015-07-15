defmodule Ecto.Integration.MigrationTest do
  use ExUnit.Case

  alias Ecto.Integration.TestRepo

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

  defmodule AlterForeignKeyMigration do
    use Ecto.Migration

    def up do
      create table(:alfter_fk_users)

      create table(:alfter_fk_posts) do
        add :alfter_fk_user_id, :id
      end

      alter table(:alfter_fk_posts) do
        modify :alfter_fk_user_id, references(:alfter_fk_users, on_delete: :nilify_all)
      end

      execute "INSERT INTO alfter_fk_users (id) VALUES ('1')"
      execute "INSERT INTO alfter_fk_posts (id, alfter_fk_user_id) VALUES ('1', '1')"
      execute "DELETE FROM alfter_fk_users"
    end

    def down do
      drop table(:alfter_fk_posts)
      drop table(:alfter_fk_users)
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

  defmodule OnDeleteMigration do
    use Ecto.Migration

    def up do
      create table(:parent1)
      create table(:parent2)

      create table(:ref_migration) do
        add :parent1, references(:parent1, on_delete: :nilify_all)
        add :parent2, references(:parent2, on_delete: :delete_all)
      end
    end

    def down do
      drop table(:ref_migration)
      drop table(:parent1)
      drop table(:parent2)
    end
  end

  defmodule RenameMigration do
    use Ecto.Migration

    @table_current table(:posts_migration)
    @table_new table(:new_posts_migration)

    def up do
      assert false == exists? @table_current
      create @table_current
      rename @table_current, @table_new
      assert true == exists? @table_new
      assert false == exists? @table_current
    end

    def down do
      drop @table_new
      assert false == exists? @table_new
    end
  end

  defmodule NoSQLMigration do
    use Ecto.Migration

    def up do
      assert_raise ArgumentError, ~r"does not support keyword lists in :options", fn ->
        create table(:collection, options: [capped: true])
      end

      assert_raise ArgumentError, ~r"does not support keyword lists in execute", fn ->
        execute create: "collection"
      end
    end
  end

  defmodule Parent do
    use Ecto.Model

    schema "parent" do
    end
  end

  import Ecto.Query, only: [from: 2]
  import Ecto.Migrator, only: [up: 4, down: 4]

  test "create and drop table and indexes" do
    assert :ok == up(TestRepo, 20050906120000, CreateMigration, log: false)
    assert :ok == down(TestRepo, 20050906120000, CreateMigration, log: false)
  end

  test "supports references" do
    assert :ok == up(TestRepo, 20050906120000, OnDeleteMigration, log: false)

    parent1 = TestRepo.insert! Ecto.Model.put_source(%Parent{}, "parent1")
    parent2 = TestRepo.insert! Ecto.Model.put_source(%Parent{}, "parent2")

    writer = "INSERT INTO ref_migration (parent1, parent2) VALUES (#{parent1.id}, #{parent2.id})"
    Ecto.Adapters.SQL.query TestRepo, writer, []

    reader = from r in "ref_migration", select: {r.parent1, r.parent2}
    assert TestRepo.all(reader) == [{parent1.id, parent2.id}]

    TestRepo.delete!(parent1)
    assert TestRepo.all(reader) == [{nil, parent2.id}]

    TestRepo.delete!(parent2)
    assert TestRepo.all(reader) == []

    assert :ok == down(TestRepo, 20050906120000, OnDeleteMigration, log: false)
  end

  test "raises on NoSQL migrations" do
    assert :ok == up(TestRepo, 20150704120000, NoSQLMigration, log: false)
  end

  @tag :add_column
  test "add column" do
    assert :ok == up(TestRepo, 20070906120000, AddColumnMigration, log: false)
    assert 2 == TestRepo.one from p in "add_col_migration", select: p.to_be_added
    :ok = down(TestRepo, 20070906120000, AddColumnMigration, log: false)
  end

  @tag :modify_column
  test "modify column" do
    assert :ok == up(TestRepo, 20080906120000, AlterColumnMigration, log: false)
    assert "foo" == TestRepo.one from p in "alter_col_migration", select: p.to_be_modified
    :ok = down(TestRepo, 20080906120000, AlterColumnMigration, log: false)
  end

  @tag :modify_foreign_key
  test "modify foreign key" do
    assert :ok == up(TestRepo, 20130802170000, AlterForeignKeyMigration, log: false)
    assert nil == TestRepo.one from p in "alfter_fk_posts", select: p.alfter_fk_user_id
    :ok = down(TestRepo, 20130802170000, AlterForeignKeyMigration, log: false)
  end

  @tag :remove_column
  test "remove column" do
    assert :ok == up(TestRepo, 20090906120000, DropColumnMigration, log: false)
    assert catch_error(TestRepo.one from p in "drop_col_migration", select: p.to_be_removed)
    :ok = down(TestRepo, 20090906120000, DropColumnMigration, log: false)
  end

  @tag :rename
  test "rename table" do
    assert :ok == up(TestRepo, 20150712120000, RenameMigration, log: false)
    assert :ok == down(TestRepo, 20150712120000, RenameMigration, log: false)
  end
end
