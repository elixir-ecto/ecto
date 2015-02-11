Code.require_file "../../test/support/file_helpers.exs", __DIR__

defmodule Ecto.Integration.MigrationTest do
  use Ecto.Integration.Case

  import Support.FileHelpers
  import Ecto.Migrator, only: [migrated_versions: 1]
  require Ecto.Integration.TestRepo, as: TestRepo

  defmodule GoodMigration do
    use Ecto.Migration

    def up do
      table = table(:barebones)

      assert exists? table
      drop table
      refute exists? table

      create table do
        add :name, :text
        add :other, :text
      end

      alter table do
        modify :name, :string
        remove :other
        add :author, :string
      end

      index = index(:barebones, [:author])
      refute exists? index
      create index
      assert exists? index
      drop index
      refute exists? index
    end

    def down do
      drop table(:barebones)
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

    File.write! "#{num}_migration.exs", """
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
