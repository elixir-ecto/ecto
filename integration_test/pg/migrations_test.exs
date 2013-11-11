defmodule Ecto.Integration.MigrationsTest do
  use Ecto.Integration.Postgres.Case

  import Support.FileHelpers
  alias Ecto.Adapters.Postgres

  defmodule GoodMigration do
    use Ecto.Migration

    def up do
      "CREATE TABLE migrations_test(id serial primary key, name text)"
    end

    def down do
      "DROP table migrations_test"
    end
  end

  defmodule BadMigration do
    use Ecto.Migration

    def up do
      "CREATE WHAT"
    end

    def down do
      "DROP table migrations_test"
    end
  end

  @good_migration """
    defmodule Ecto.MigrationTest.GoodMigration~B do
      use Ecto.Migration

      def up do
        [ "CREATE TABLE IF NOT EXISTS migrations_test(id serial primary key, name text)",
          "INSERT INTO migrations_test (name) VALUES ('inserted')" ]
      end

      def down do
        []
      end
    end
  """

  @bad_migration """
    defmodule Ecto.MigrationTest.BadMigration~B do
      use Ecto.Migration

      def up do
        "error"
      end

      def down do
        "error"
      end
    end
  """

  import Ecto.Migrator

  test "migrations up and down" do
    assert migrated_versions(TestRepo) == []
    assert up(TestRepo, 20080906120000, GoodMigration) == :ok
    assert migrated_versions(TestRepo) == [20080906120000]
    assert up(TestRepo, 20080906120000, GoodMigration) == :already_up
    assert migrated_versions(TestRepo) == [20080906120000]
    assert down(TestRepo, 20080906120001, GoodMigration) == :missing_up
    assert migrated_versions(TestRepo) == [20080906120000]
    assert down(TestRepo, 20080906120000, GoodMigration) == :ok
    assert migrated_versions(TestRepo) == []
  end

  test "bad migration" do
    assert_raise Postgrex.Error, fn ->
      up(TestRepo, 20080906120000, BadMigration)
    end
  end

  test "run all migrations" do
    in_tmp fn path ->
      create_migration(42, @good_migration)
      create_migration(43, @good_migration)
      assert [42, 43] = run_up(TestRepo, path)

      create_migration(44, @good_migration)
      assert [44] = run_up(TestRepo, path)

      assert [] = run_up(TestRepo, path)

      assert Postgrex.Result[num_rows: 3] =
        Postgres.query(TestRepo, "SELECT * FROM migrations_test")
    end
  end

  test "bad migration raises" do
    in_tmp fn path ->
      create_migration(42, @bad_migration)
      assert_raise Postgrex.Error, fn ->
        run_up(TestRepo, path)
      end
    end
  end

  defp migrated_versions(repo) do
    repo.adapter.migrated_versions(repo)
  end

  defp create_migration(num, contents) do
    File.write!("#{num}_migration.exs", :io_lib.format(contents, [num]))
  end
end
