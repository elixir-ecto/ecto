Code.require_file "../../test/support/file_helpers.exs", __DIR__

defmodule Ecto.Integration.MigrationTest do
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

  defmodule MigrationTestTable do
    use Ecto.Model

    schema "migration_test_table" do
      field :to_be_modified, :string
      field :to_be_removed, :integer
    end
  end

  @tag :modify_column
  test "modify column" do
    import Ecto.Query, only: [from: 2]

    in_tmp fn path ->
      migrations = [
        create_table(55),
        modify_column(56),
      ]

      assert [55, 56] = run(TestRepo, path, :up, all: true, log: false)
      purge migrations
      assert "foo" == TestRepo.one from p in MigrationTestTable, select: p.to_be_modified
    end
  end

  @tag :remove_column
  test "remove column" do
    import Ecto.Query, only: [from: 2]

    in_tmp fn path ->
      migrations = [
        create_table(57),
        remove_column(58),
      ]

      assert [57, 58] = run(TestRepo, path, :up, all: true, log: false)
      purge migrations
      assert catch_error(TestRepo.one from p in MigrationTestTable, select: p.to_be_removed)
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

  defp create_table(num) do
    module = Module.concat(__MODULE__, "Migration#{num}")

    File.write! "#{num}_migration_#{num}.exs", """
    defmodule #{module} do
      use Ecto.Migration

      def change do
        create table(:migration_test_table) do
          add :to_be_modified, :integer
          add :to_be_removed, :integer
        end
      end
    end
    """

    module
  end

  defp modify_column(num) do
    module = Module.concat(__MODULE__, "Migration#{num}")

    File.write! "#{num}_migration_#{num}.exs", """
    defmodule #{module} do
      use Ecto.Migration

      def up do
        alter table(:migration_test_table) do
          modify :to_be_modified, :string
        end
        execute "INSERT INTO migration_test_table (to_be_modified) VALUES ('foo')"
      end

      def down do
        :ok
      end
    end
    """

    module
  end

  defp remove_column(num) do
    module = Module.concat(__MODULE__, "Migration#{num}")

    File.write! "#{num}_migration_#{num}.exs", """
    defmodule #{module} do
      use Ecto.Migration

      def up do
        alter table(:migration_test_table) do
          remove :to_be_removed
        end
        execute "INSERT INTO migration_test_table (to_be_modified) VALUES (1)"
      end

      def down do
        :ok
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
