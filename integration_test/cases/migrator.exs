Code.require_file "../support/file_helpers.exs", __DIR__

defmodule Ecto.Integration.MigratorTest do
  use Ecto.Integration.Case

  import Support.FileHelpers
  import Ecto.Migrator, only: [migrated_versions: 1]

  alias Ecto.Integration.PoolRepo
  alias Ecto.Migration.SchemaMigration

  setup do
    PoolRepo.delete_all(SchemaMigration)
    :ok
  end

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
    up(PoolRepo, 20100906120000, GoodMigration, log: false)

    [migration] = PoolRepo.all(SchemaMigration)
    assert migration.version == 20100906120000
    assert migration.inserted_at
  end

  test "migrations up and down" do
    assert migrated_versions(PoolRepo) == []
    assert up(PoolRepo, 20100906120000, GoodMigration, log: false) == :ok

    assert migrated_versions(PoolRepo) == [20100906120000]
    assert up(PoolRepo, 20100906120000, GoodMigration, log: false) == :already_up
    assert migrated_versions(PoolRepo) == [20100906120000]
    assert down(PoolRepo, 21100906120000, GoodMigration, log: false) == :already_down
    assert migrated_versions(PoolRepo) == [20100906120000]
    assert down(PoolRepo, 20100906120000, GoodMigration, log: false) == :ok
    assert migrated_versions(PoolRepo) == []
  end

  test "bad migration" do
    assert catch_error(up(PoolRepo, 20100906120000, BadMigration, log: false))
  end

  test "run up to/step migration" do
    in_tmp fn path ->
      create_migration(47)
      create_migration(48)

      assert [47] = run(PoolRepo, path, :up, step: 1, log: false)
      assert count_entries() == 1

      assert [48] = run(PoolRepo, path, :up, to: 48, log: false)
    end
  end

  test "run down to/step migration" do
    in_tmp fn path ->
      migrations = [
        create_migration(49),
        create_migration(50),
      ]

      assert [49, 50] = run(PoolRepo, path, :up, all: true, log: false)
      purge migrations

      assert [50] = run(PoolRepo, path, :down, step: 1, log: false)
      purge migrations

      assert count_entries() == 1
      assert [50] = run(PoolRepo, path, :up, to: 50, log: false)
    end
  end

  test "runs all migrations" do
    in_tmp fn path ->
      migrations = [
        create_migration(53),
        create_migration(54),
      ]

      assert [53, 54] = run(PoolRepo, path, :up, all: true, log: false)
      assert [] = run(PoolRepo, path, :up, all: true, log: false)
      purge migrations

      assert [54, 53] = run(PoolRepo, path, :down, all: true, log: false)
      purge migrations

      assert count_entries() == 0
      assert [53, 54] = run(PoolRepo, path, :up, all: true, log: false)
    end
  end

  defp count_entries() do
    length Process.get(:migrations)
  end

  defp create_migration(num) do
    module = Module.concat(__MODULE__, "Migration#{num}")

    File.write! "#{num}_migration_#{num}.exs", """
    defmodule #{module} do
      use Ecto.Migration


      def up do
        update &[#{num}|&1]
      end

      def down do
        update &List.delete(&1, #{num})
      end

      defp update(fun) do
        Process.put(:migrations, fun.(Process.get(:migrations) || []))
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
