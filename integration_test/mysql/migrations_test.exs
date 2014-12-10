defmodule Ecto.Integration.Mysql.MigrationsTest do
  use Ecto.Integration.Mysql.Case

  import Support.FileHelpers
  import ExUnit.CaptureIO
  alias Ecto.Adapters.Mysql
  alias Emysql

  defmodule GoodMigration do
    use Ecto.Migration

    def up do
      "CREATE TABLE migrations_test (id int AUTO_INCREMENT, name text, PRIMARY KEY(id))"
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
        [ "CREATE TABLE IF NOT EXISTS migrations_test (id int AUTO_INCREMENT, name text, PRIMARY KEY(id))",
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

  setup do
    Application.put_env(:elixir, :ansi_enabled, false)
    on_exit fn ->
      Application.delete_env(:elixir, :ansi_enabled)
    end
  end

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
    assert_raise Mysql.Error, fn ->
      up(TestRepo, 20080906120000, BadMigration)
    end
  end

  test "run up all migrations" do
    in_tmp fn path ->
      create_migration(42, @good_migration)
      create_migration(43, @good_migration)

      assert capture_io(fn ->
        assert [42, 43] = run(TestRepo, path, :up, all: true)
      end) == "* running UP 42_migration.exs\n* running UP 43_migration.exs\n"

      create_migration(44, @good_migration)

      assert capture_io(fn ->
        assert [44] = run(TestRepo, path, :up, all: true)
      end) == "* running UP 44_migration.exs\n"

      assert capture_io(fn ->
        assert [] = run(TestRepo, path, :up, all: true)
      end) == ""

      assert %Mysql.Result{num_rows: 3} =
        Mysql.query(TestRepo, "SELECT * FROM migrations_test", [])
    end
  end

  test "run up to migration" do
    in_tmp fn path ->
      create_migration(45, @good_migration)
      create_migration(46, @good_migration)

      assert capture_io(fn ->
        assert [45] = run(TestRepo, path, :up, to: 45)
      end) == "* running UP 45_migration.exs\n"

      assert %Mysql.Result{num_rows: 1} =
        Mysql.query(TestRepo, "SELECT * FROM migrations_test", [])

      assert capture_io(fn ->
        assert [46] = run(TestRepo, path, :up, to: 46)
      end) == "* running UP 46_migration.exs\n"
    end
  end

  test "run up 1 migration" do
    in_tmp fn path ->
      create_migration(47, @good_migration)
      create_migration(48, @good_migration)

      assert capture_io(fn ->
        assert [47] = run(TestRepo, path, :up, step: 1)
      end) == "* running UP 47_migration.exs\n"

      assert %Mysql.Result{num_rows: 1} =
        Mysql.query(TestRepo, "SELECT * FROM migrations_test", [])

      assert capture_io(fn ->
        assert [48] = run(TestRepo, path, :up, to: 48)
      end) == "* running UP 48_migration.exs\n"
    end
  end

  test "run down 1 migration" do
    in_tmp fn path ->
      migrations = [
        create_migration(49, @good_migration),
        create_migration(50, @good_migration),
      ]
      assert capture_io(fn ->
        assert [49, 50] = run(TestRepo, path, :up, all: true)
      end) == "* running UP 49_migration.exs\n* running UP 50_migration.exs\n"

      purge migrations

      assert capture_io(fn ->
        assert [50] = run(TestRepo, path, :down, step: 1)
      end) == "* running DOWN 50_migration.exs\n"

      purge migrations

      assert %Mysql.Result{rows: _rows} =
        Mysql.query(TestRepo, "SELECT * FROM migrations_test", [])

      assert capture_io(fn ->
        assert [50] = run(TestRepo, path, :up, to: 50)
      end) == "* running UP 50_migration.exs\n"
    end
  end

  test "run down to migration" do
    in_tmp fn path ->
      migrations = [
        create_migration(51, @good_migration),
        create_migration(52, @good_migration),
      ]

      assert capture_io(fn ->
        assert [51, 52] = run(TestRepo, path, :up, all: true)
      end) == "* running UP 51_migration.exs\n* running UP 52_migration.exs\n"

      purge migrations

      assert capture_io(fn ->
        assert [52] = run(TestRepo, path, :down, to: 52)
      end) == "* running DOWN 52_migration.exs\n"

      purge migrations

      # assert %Mysql.Result{num_rows: 1} =
      #   Mysql.query(TestRepo, "SELECT * FROM migrations_test", [])

      assert capture_io(fn ->
        assert [52] = run(TestRepo, path, :up, to: 52)
      end) == "* running UP 52_migration.exs\n"
    end
  end

  test "run down all migrations" do
    in_tmp fn path ->
      migrations = [
        create_migration(53, @good_migration),
        create_migration(54, @good_migration),
      ]

      assert capture_io(fn ->
        assert [53, 54] = run(TestRepo, path, :up, all: true)
      end) == "* running UP 53_migration.exs\n* running UP 54_migration.exs\n"

      purge migrations

      assert capture_io(fn ->
        assert [54, 53] = run(TestRepo, path, :down, all: true)
      end) == "* running DOWN 54_migration.exs\n* running DOWN 53_migration.exs\n"

      purge migrations

      # assert %Emysql.Result{num_rows: 0} =
      #   Mysql.query(TestRepo, "SELECT * FROM migrations_test", [])

      assert capture_io(fn ->
        assert [53, 54] = run(TestRepo, path, :up, all: true)
      end) == "* running UP 53_migration.exs\n* running UP 54_migration.exs\n"
    end
  end

  test "bad migration raises" do
    in_tmp fn path ->
      create_migration(55, @bad_migration)
      assert_raise Mysql.Error, fn ->
        capture_io(fn ->
          run(TestRepo, path, :up, all: true)
        end)
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
     Enum.each(List.wrap(modules), fn m ->
       :code.delete m
       :code.purge m
     end)
  end
end

