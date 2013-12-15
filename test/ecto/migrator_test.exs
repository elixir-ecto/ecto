defmodule Ecto.MigratorTest do
  use ExUnit.Case

  import Support.FileHelpers

  import Ecto.Migrator

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
    assert up(ProcessRepo, 0, Migration) == :ok
    assert up(ProcessRepo, 1, Migration) == :already_up
  end

  test "down invokes the repository adapter with down commands" do
    assert down(ProcessRepo, 0, Migration) == :already_down
    assert down(ProcessRepo, 1, Migration) == :ok
  end

  test "expects files starting with an integer" do
    in_tmp fn path ->
      create_migration "a_sample.exs"
      assert run(ProcessRepo, path, :up) == []
    end
  end

  test "fails if there is no migration in file" do
    in_tmp fn path ->
      File.write! "13_sample.exs", ":ok"
      assert_raise Ecto.MigrationError, "file 13_sample.exs does not contain any Ecto.Migration", fn ->
        run(ProcessRepo, path, :up)
      end
    end
  end

  test "fails if there are duplicated versions" do
    in_tmp fn path ->
      create_migration "13_hello.exs"
      create_migration "13_other.exs"
      assert_raise Ecto.MigrationError, "migrations can't be executed, version 13 is duplicated", fn ->
        run(ProcessRepo, path, :up)
      end
    end
  end

  test "upwards migrations without strategies runs all" do
    in_tmp fn path ->
      create_migration "13_up_without_strategies.exs"
      create_migration "14_up_without_strategies.exs"
      assert run(ProcessRepo, path, :up) == [13, 14]
    end
  end

  test "downwards migrations without strategies revert one" do
    in_tmp fn path ->
      create_migration "1_down_without_strategies.exs"
      create_migration "2_down_without_strategies.exs"
      create_migration "3_down_without_strategies.exs"
      assert run(ProcessRepo, path, :down) == [3]
    end
  end

  test "upwards migrations skips migrations that are already up" do
    in_tmp fn path ->
      create_migration "1_sample.exs"
      assert run(ProcessRepo, path, :up) == []
    end
  end

  test "downwards migrations skips migrations that are already down" do
    in_tmp fn path ->
      create_migration "1_sample.exs"
      create_migration "4_sample.exs"
      assert run(ProcessRepo, path, :down, all: true) == [1]
    end
  end

  test "stepwise migrations stop before all have been run" do
    in_tmp fn path ->
      create_migration "13_step_premature_end.exs"
      create_migration "14_step_premature_end.exs"
      assert run(ProcessRepo, path, :up, step: 1) == [13]
    end
  end

  test "stepwise migrations stop at the number of available migrations" do
    in_tmp fn path ->
      create_migration "13_step_to_the_end.exs"
      create_migration "14_step_to_the_end.exs"
      assert run(ProcessRepo, path, :up, step: 2) == [13, 14]
    end
  end

  test "stepwise migrations stop even if asked to exceed available" do
    in_tmp fn path ->
      create_migration "13_step_past_the_end.exs"
      create_migration "14_step_past_the_end.exs"
      assert run(ProcessRepo, path, :up, step: 3) == [13, 14]
    end
  end

  test "version migrations stop before all have been run" do
    in_tmp fn path ->
      create_migration "13_version_premature_end.exs"
      create_migration "14_version_premature_end.exs"
      assert run(ProcessRepo, path, :up, to: 13) == [13]
    end
  end

  test "version migrations stop at the number of available migrations" do
    in_tmp fn path ->
      create_migration "13_version_to_the_end.exs"
      create_migration "14_version_to_the_end.exs"
      assert run(ProcessRepo, path, :up, to: 14) == [13, 14]
    end
  end

  test "version migrations stop even if asked to exceed available" do
    in_tmp fn path ->
      create_migration "13_version_past_the_end.exs"
      create_migration "14_version_past_the_end.exs"
      assert run(ProcessRepo, path, :up, to: 15) == [13, 14]
    end
  end

  test "version migrations take precedence over stepwise and total migrations" do
    in_tmp fn path ->
      create_migration "13_version_precedence.exs"
      create_migration "14_version_precedence.exs"
      assert run(ProcessRepo, path, :up, to: 13, all: true, step: 2) == [13]
    end
  end

  test "stepwise migrations take precedence over total migrations" do
    in_tmp fn path ->
      create_migration "13_step_precedence.exs"
      create_migration "14_step_precedence.exs"
      assert run(ProcessRepo, path, :up, all: true, step: 1) == [13]
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
