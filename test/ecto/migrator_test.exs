defmodule Ecto.MigratorTest do
  use ExUnit.Case

  import Support.FileHelpers
  import ExUnit.CaptureIO
  import Ecto.Migrator

  defp migration_logger(:up, file) do
    IO.puts "* running UP #{file}"
  end

  defp migration_logger(:down, file) do
    IO.puts "* running DOWN #{file}"
  end
  
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
    capture_io(fn ->
      assert up(ProcessRepo, 0, Migration) == :ok
      assert up(ProcessRepo, 1, Migration) == :already_up
    end)
  end

  test "down invokes the repository adapter with down commands" do
    capture_io(fn ->
      assert down(ProcessRepo, 0, Migration) == :already_down
      assert down(ProcessRepo, 1, Migration) == :ok
    end)
  end

  test "expects files starting with an integer" do
    in_tmp fn path ->
      create_migration "a_sample.exs"
      capture_io(fn ->
        assert run(ProcessRepo, path, :up, all: true, logger: &migration_logger/2) == []
      end)
    end
  end

  test "fails if there is no migration in file" do
    in_tmp fn path ->
      File.write! "13_sample.exs", ":ok"
      assert_raise Ecto.MigrationError, "file 13_sample.exs does not contain any Ecto.Migration", fn ->
        capture_io fn -> run(ProcessRepo, path, :up, all: true, logger: &migration_logger/2) end
      end
    end
  end

  test "fails if there are duplicated versions" do
    in_tmp fn path ->
      create_migration "13_hello.exs"
      create_migration "13_other.exs"
      assert_raise Ecto.MigrationError, "migrations can't be executed, version 13 is duplicated", fn ->
        capture_io fn -> run(ProcessRepo, path, :up, all: true, logger: &migration_logger/2) end
      end
    end
  end

  test "upwards migrations skips migrations that are already up" do
    in_tmp fn path ->
      create_migration "1_sample.exs"
      capture_io fn -> assert run(ProcessRepo, path, :up, all: true, logger: &migration_logger/2) == [] end
    end
  end

  test "downwards migrations skips migrations that are already down" do
    in_tmp fn path ->
      create_migration "1_sample.exs"
      create_migration "4_sample.exs"
      capture_io(fn ->
        assert run(ProcessRepo, path, :down, all: true, logger: &migration_logger/2) == [1]
      end)
    end
  end

  test "stepwise migrations stop before all have been run" do
    in_tmp fn path ->
      create_migration "13_step_premature_end.exs"
      create_migration "14_step_premature_end.exs"
      capture_io(fn ->
        assert run(ProcessRepo, path, :up, step: 1, logger: &migration_logger/2) == [13]
      end)
    end
  end

  test "stepwise migrations stop at the number of available migrations" do
    in_tmp fn path ->
      create_migration "13_step_to_the_end.exs"
      create_migration "14_step_to_the_end.exs"
      capture_io(fn ->
        assert run(ProcessRepo, path, :up, step: 2, logger: &migration_logger/2) == [13, 14]
      end)
    end
  end

  test "stepwise migrations stop even if asked to exceed available" do
    in_tmp fn path ->
      create_migration "13_step_past_the_end.exs"
      create_migration "14_step_past_the_end.exs"
      capture_io(fn ->
        assert run(ProcessRepo, path, :up, step: 3, logger: &migration_logger/2) == [13, 14]
      end)
    end
  end

  test "version migrations stop before all have been run" do
    in_tmp fn path ->
      create_migration "13_version_premature_end.exs"
      create_migration "14_version_premature_end.exs"
      capture_io(fn ->
        assert run(ProcessRepo, path, :up, to: 13, logger: &migration_logger/2) == [13]
      end)
    end
  end

  test "version migrations stop at the number of available migrations" do
    in_tmp fn path ->
      create_migration "13_version_to_the_end.exs"
      create_migration "14_version_to_the_end.exs"
      capture_io(fn ->
        assert run(ProcessRepo, path, :up, to: 14, logger: &migration_logger/2) == [13, 14]
      end)
    end
  end

  test "version migrations stop even if asked to exceed available" do
    in_tmp fn path ->
      create_migration "13_version_past_the_end.exs"
      create_migration "14_version_past_the_end.exs"
      capture_io(fn ->
        assert run(ProcessRepo, path, :up, to: 15, logger: &migration_logger/2) == [13, 14]
      end)
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
