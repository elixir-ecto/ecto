defmodule Ecto.MigratorTest do
  use ExUnit.Case

  import Support.FileHelpers
  import ExUnit.CaptureIO
  import Ecto.Migrator

  defmodule ProcessRepo do
    @behaviour Ecto.Adapter.Migrations

    def adapter do
      __MODULE__
    end

    def migrated_versions(__MODULE__) do
      Process.get(:migrated_versions)
    end
    def insert_migration_version(__MODULE__, _version), do: nil
    def delete_migration_version(__MODULE__, _version), do: nil
    def execute_migration(__MODULE__, _command),        do: nil

    def transaction(fun), do: fun.()
  end

  defmodule Migration do
    use Ecto.Migration

    def up do
      execute "up"
    end

    def down do
      execute "down"
    end
  end

  defmodule ReversibleMigration do
    use Ecto.Migration

    def change do
      create table(:posts) do
        add :name, :string
      end
    end
  end

  defmodule InvalidMigration do
    use Ecto.Migration
  end

  defmodule MockRunner do
    use GenServer

    def start_link do
      GenServer.start_link(__MODULE__, [], [name: Ecto.Migration.Runner])
    end

    def handle_call({:direction, direction}, _from, state) do
      {:reply, {:changed, direction}, state}
    end

    def handle_call({:execute, command}, _from, state) do
      {:reply, {:executed, command}, state}
    end
  end

  setup do
    {:ok, _} = MockRunner.start_link
    Process.put(:migrated_versions, [1, 2, 3])
    :ok
  end

  test "up invokes the repository adapter with up commands" do
    capture_io(fn ->
      assert up(ProcessRepo, 0, Migration) == :ok
      assert up(ProcessRepo, 1, Migration) == :already_up
      assert up(ProcessRepo, 0, ReversibleMigration) == :ok
    end)
  end

  test "down invokes the repository adapter with down commands" do
    capture_io(fn ->
      assert down(ProcessRepo, 0, Migration) == :already_down
      assert down(ProcessRepo, 1, Migration) == :ok
      assert down(ProcessRepo, 1, ReversibleMigration) == :ok
    end)
  end

  test "up raises error when missing up/0 and change/0" do
    assert_raise Ecto.MigrationError, fn ->
      Ecto.Migrator.up(ProcessRepo, 0, InvalidMigration)
    end
  end

  test "down raises error when missing down/0 and change/0" do
    assert_raise Ecto.MigrationError, fn ->
      Ecto.Migrator.down(ProcessRepo, 1, InvalidMigration)
    end
  end

  test "expects files starting with an integer" do
    in_tmp fn path ->
      create_migration "a_sample.exs"
      capture_io(fn ->
        assert run(ProcessRepo, path, :up, all: true) == []
      end)
    end
  end

  test "fails if there is no migration in file" do
    in_tmp fn path ->
      File.write! "13_sample.exs", ":ok"
      assert_raise Ecto.MigrationError, "file 13_sample.exs does not contain any Ecto.Migration", fn ->
        capture_io fn -> run(ProcessRepo, path, :up, all: true) end
      end
    end
  end

  test "fails if there are duplicated versions" do
    in_tmp fn path ->
      create_migration "13_hello.exs"
      create_migration "13_other.exs"
      assert_raise Ecto.MigrationError, "migrations can't be executed, version 13 is duplicated", fn ->
        capture_io fn -> run(ProcessRepo, path, :up, all: true) end
      end
    end
  end

  test "upwards migrations skips migrations that are already up" do
    in_tmp fn path ->
      create_migration "1_sample.exs"
      capture_io fn -> assert run(ProcessRepo, path, :up, all: true) == [] end
    end
  end

  test "downwards migrations skips migrations that are already down" do
    in_tmp fn path ->
      create_migration "1_sample.exs"
      create_migration "4_sample.exs"
      capture_io(fn ->
        assert run(ProcessRepo, path, :down, all: true) == [1]
      end)
    end
  end

  test "stepwise migrations stop before all have been run" do
    in_tmp fn path ->
      create_migration "13_step_premature_end.exs"
      create_migration "14_step_premature_end.exs"
      capture_io(fn ->
        assert run(ProcessRepo, path, :up, step: 1) == [13]
      end)
    end
  end

  test "stepwise migrations stop at the number of available migrations" do
    in_tmp fn path ->
      create_migration "13_step_to_the_end.exs"
      create_migration "14_step_to_the_end.exs"
      capture_io(fn ->
        assert run(ProcessRepo, path, :up, step: 2) == [13, 14]
      end)
    end
  end

  test "stepwise migrations stop even if asked to exceed available" do
    in_tmp fn path ->
      create_migration "13_step_past_the_end.exs"
      create_migration "14_step_past_the_end.exs"
      capture_io(fn ->
        assert run(ProcessRepo, path, :up, step: 3) == [13, 14]
      end)
    end
  end

  test "version migrations stop before all have been run" do
    in_tmp fn path ->
      create_migration "13_version_premature_end.exs"
      create_migration "14_version_premature_end.exs"
      capture_io(fn ->
        assert run(ProcessRepo, path, :up, to: 13) == [13]
      end)
    end
  end

  test "version migrations stop at the number of available migrations" do
    in_tmp fn path ->
      create_migration "13_version_to_the_end.exs"
      create_migration "14_version_to_the_end.exs"
      capture_io(fn ->
        assert run(ProcessRepo, path, :up, to: 14) == [13, 14]
      end)
    end
  end

  test "version migrations stop even if asked to exceed available" do
    in_tmp fn path ->
      create_migration "13_version_past_the_end.exs"
      create_migration "14_version_past_the_end.exs"
      capture_io(fn ->
        assert run(ProcessRepo, path, :up, to: 15) == [13, 14]
      end)
    end
  end

  defp create_migration(name) do
    File.write! name, """
    defmodule Ecto.MigrationTest.S#{Path.rootname(name)} do
      use Ecto.Migration

      def up do
        create table(:products) do
          add :name, :string
        end
      end

      def down do
        drop table(:products)
      end
    end
    """
  end
end
