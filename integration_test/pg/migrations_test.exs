defmodule Ecto.Integration.MigrationsTest do
  use Ecto.Integration.Postgres.Case

  import Support.FileHelpers
  import Ecto.Migrator, only: [migrated_versions: 1]

  defmodule GoodMigration do
    use Ecto.Migration

    def up do
      table = table(:migrations_test)

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
        add :counter, :integer
      end

      index = index(:migrations_test, [:counter])
      refute exists? index
      create index
      assert exists? index
      drop index
      refute exists? index
    end

    def down do
      drop table(:migrations_test)
    end
  end

  defmodule BadMigration do
    use Ecto.Migration

    def change do
      execute "CREATE WHAT"
    end
  end

  import Ecto.Migrator

  setup do
    Application.put_env(:elixir, :ansi_enabled, false)

    on_exit fn ->
      Application.delete_env(:elixir, :ansi_enabled)
    end
  end

  test "schema migration" do
    [migration] = TestRepo.all(Ecto.Migration.SchemaMigration)
    assert migration.version == 0
    assert migration.inserted_at
  end

  test "migrations up and down" do
    assert migrated_versions(TestRepo) == [0]
    assert up(TestRepo, 20080906120000, GoodMigration, level: :none) == :ok

    assert migrated_versions(TestRepo) == [0, 20080906120000]
    assert up(TestRepo, 20080906120000, GoodMigration, level: :none) == :already_up
    assert migrated_versions(TestRepo) == [0, 20080906120000]
    assert down(TestRepo, 20080906120001, GoodMigration, level: :none) == :already_down
    assert migrated_versions(TestRepo) == [0, 20080906120000]
    assert down(TestRepo, 20080906120000, GoodMigration, level: :none) == :ok
    assert migrated_versions(TestRepo) == [0]
  end

  test "bad migration" do
    assert_raise Postgrex.Error, fn ->
      up(TestRepo, 20080906120000, BadMigration, level: :none)
    end
  end

  test "run up to/step migration" do
    in_tmp fn path ->
      create_migration(47)
      create_migration(48)

      assert [47] = run(TestRepo, path, :up, step: 1, level: :none)
      assert count_entries() == 1

      assert [48] = run(TestRepo, path, :up, to: 48, level: :none)
    end
  end

  test "run down to/step migration" do
    in_tmp fn path ->
      migrations = [
        create_migration(49),
        create_migration(50),
      ]

      assert [49, 50] = run(TestRepo, path, :up, all: true, level: :none)
      purge migrations

      assert [50] = run(TestRepo, path, :down, step: 1, level: :none)
      purge migrations

      assert count_entries() == 1
      assert [50] = run(TestRepo, path, :up, to: 50, level: :none)
    end
  end

  test "runs all migrations" do
    in_tmp fn path ->
      migrations = [
        create_migration(53),
        create_migration(54),
      ]

      assert [53, 54] = run(TestRepo, path, :up, all: true, level: :none)
      assert [] = run(TestRepo, path, :up, all: true, level: :none)
      purge migrations

      assert [54, 53] = run(TestRepo, path, :down, all: true, level: :none)
      purge migrations

      assert count_entries() == 0
      assert [53, 54] = run(TestRepo, path, :up, all: true, level: :none)
    end
  end

  defp count_entries() do
    import Ecto.Query, only: [from: 2]
    TestRepo.one! from p in "migrations_test", select: count(1)
  end

  defp create_migration(num) do
    module = Module.concat(__MODULE__, "Migration#{num}")

    File.write! "#{num}_migration.exs", """
    defmodule #{module} do
      use Ecto.Migration

      def up do
        execute "INSERT INTO migrations_test (name) VALUES ('inserted')"
      end

      def down do
        execute "DELETE FROM migrations_test WHERE id IN (SELECT id FROM migrations_test LIMIT 1)"
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
