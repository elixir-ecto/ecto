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
    defmodule ~s do
      use Ecto.Migration

      def up do
        [ "CREATE TABLE IF NOT EXISTS migrations_test(id serial primary key, name text)",
          "INSERT INTO migrations_test (name) VALUES ('inserted')" ]
      end

      def down do
        [ "DELETE FROM migrations_test WHERE id IN ( SELECT id FROM migrations_test LIMIT 1 )" ]
      end
    end
  """

  @bad_migration """
    defmodule ~s do
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

  test "run up all migrations" do
    in_tmp fn path ->
      create_migration(42, @good_migration)
      create_migration(43, @good_migration)
      assert [42, 43] = run(TestRepo, path, :up, { :all, true })

      create_migration(44, @good_migration)
      assert [44] = run(TestRepo, path, :up, { :all, true })

      assert [] = run(TestRepo, path, :up, { :all, true })

      assert Postgrex.Result[num_rows: 3] =
        Postgres.query(TestRepo, "SELECT * FROM migrations_test")
    end
  end

  test "run up to migration" do
    in_tmp fn path ->
      create_migration(45, @good_migration)
      create_migration(46, @good_migration)
      assert [45] = run(TestRepo, path, :up, { :to, 45 })

      assert Postgrex.Result[num_rows: 1] =
        Postgres.query(TestRepo, "SELECT * FROM migrations_test")

      assert [46] = run(TestRepo, path, :up, { :to, 46 })
    end
  end

  test "run up 1 migration" do
    in_tmp fn path ->
      create_migration(47, @good_migration)
      create_migration(48, @good_migration)
      assert [47] = run(TestRepo, path, :up, { :step, 1 })

      assert Postgrex.Result[num_rows: 1] =
        Postgres.query(TestRepo, "SELECT * FROM migrations_test")

      assert [48] = run(TestRepo, path, :up, { :to, 48 })
    end
  end

  test "run down 1 migration" do
    in_tmp fn path ->
      migrations = [
        create_migration(49, @good_migration),
        create_migration(50, @good_migration),
      ]
      assert [49, 50] = run(TestRepo, path, :up, { :all, true })
      purge migrations

      assert [50] = run(TestRepo, path, :down, { :step, 1 })
      purge migrations

      assert Postgrex.Result[num_rows: 1] =
        Postgres.query(TestRepo, "SELECT * FROM migrations_test")

      assert [50] = run(TestRepo, path, :up, { :to, 50 })
    end
  end

  test "run down to migration" do
    in_tmp fn path ->
      migrations = [
        create_migration(51, @good_migration),
        create_migration(52, @good_migration),
      ]

      assert [51, 52] = run(TestRepo, path, :up, { :all, true })
      purge migrations

      assert [52] = run(TestRepo, path, :down, { :to, 52 })
      purge migrations

      assert Postgrex.Result[num_rows: 1] =
        Postgres.query(TestRepo, "SELECT * FROM migrations_test")

      assert [52] = run(TestRepo, path, :up, { :to, 52 })
    end
  end

  test "run down all migrations" do
    in_tmp fn path ->
      migrations = [
        create_migration(53, @good_migration),
        create_migration(54, @good_migration),
      ]
      assert [53, 54] = run(TestRepo, path, :up, { :all, true })
      purge migrations

      assert [54, 53] = run(TestRepo, path, :down, { :all, true })
      purge migrations

      assert Postgrex.Result[num_rows: 0] =
        Postgres.query(TestRepo, "SELECT * FROM migrations_test")

      assert [53, 54] = run(TestRepo, path, :up, { :all, true })
    end
  end

  test "bad migration raises" do
    in_tmp fn path ->
      create_migration(55, @bad_migration)
      assert_raise Postgrex.Error, fn ->
        run(TestRepo, path, :up, { :all, true })
      end
    end
  end

  defp migrated_versions(repo) do
    repo.adapter.migrated_versions(repo)
  end

  defp create_migration(num, contents) do
    migration = Module.concat(__MODULE__, "Migration#{num}")
    File.write!("#{num}_migration.exs", :io_lib.format(contents, [migration]))
    migration
  end

  defp purge(modules) do
    modules
      |> List.wrap
      |> Enum.each( fn m ->
           :code.delete m
           :code.purge m
         end )
  end
end
