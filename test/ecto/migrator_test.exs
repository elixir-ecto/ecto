defmodule Ecto.MigratorTest do
  use ExUnit.Case

  import Support.FileHelpers

  defmodule ProcessRepo do
    @behaviour Ecto.Adapter.Migrations

    def adapter do
      __MODULE__
    end

    def migrate_up(__MODULE__, id, ["up"]) do
      versions = migrated_versions(__MODULE__)
      if id in versions, do: :already_up, else: :ok
    end

    def migrate_down(__MODULE__, id, ["down"]) do
      versions = migrated_versions(__MODULE__)
      if id in versions, do: :ok, else: :already_down
    end

    def migrated_versions(__MODULE__) do
      Process.get(:migrated_versions)
    end
  end

  defmodule Migration do
    def up do
      "up"
    end

    def down do
      "down"
    end
  end

  setup do
    Process.put(:migrated_versions, [1, 2, 3])
    :ok
  end

  test "up invokes the repository adapter with up commands" do
    assert Ecto.Migrator.up(ProcessRepo, 0, Migration) == :ok
    assert Ecto.Migrator.up(ProcessRepo, 1, Migration) == :already_up
  end

  test "down invokes the repository adapter with down commands" do
    assert Ecto.Migrator.down(ProcessRepo, 0, Migration) == :already_down
    assert Ecto.Migrator.down(ProcessRepo, 1, Migration) == :ok
  end

  test "run_up runs all migrations inside a directory" do
    in_tmp fn path ->
      create_migration "13_sample.exs"
      assert Ecto.Migrator.run_up(ProcessRepo, path) == [13]
    end
  end

  test "run_up skip migrations that are already up" do
    in_tmp fn path ->
      create_migration "1_sample.exs"
      assert Ecto.Migrator.run_up(ProcessRepo, path) == []
    end
  end

  test "expects files starting with an integer" do
    in_tmp fn path ->
      create_migration "a_sample.exs"
      assert Ecto.Migrator.run_up(ProcessRepo, path) == []
    end
  end

  test "fails if there is no migration in file" do
    in_tmp fn path ->
      File.write! "13_sample.exs", ":ok"
      assert_raise Ecto.MigrationError, "file 13_sample.exs does not contain any Ecto.Migration", fn ->
        Ecto.Migrator.run_up(ProcessRepo, path)
      end
    end
  end

  test "fails if there are duplicated versions" do
    in_tmp fn path ->
      create_migration "13_hello.exs"
      create_migration "13_other.exs"
      assert_raise Ecto.MigrationError, "migrations can't be executed, version 13 is duplicated", fn ->
        Ecto.Migrator.run_up(ProcessRepo, path)
      end
    end
  end

  defp create_migration(name) do
    File.write! name, """
    defmodule Ecto.MigrationTest.S#{Path.rootname(name)} do
      use Ecto.Migration

      def up do
        "up"
      end

      def down do
        "down"
      end
    end
    """
  end
end
