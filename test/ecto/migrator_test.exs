Code.require_file "../support/mock_repo.exs", __DIR__

defmodule Ecto.MigratorTest do
  use ExUnit.Case

  import Support.FileHelpers
  import ExUnit.CaptureIO
  import Ecto.Migrator
  alias Ecto.MockRepo

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

  setup do
    Process.put(:migrated_versions, [1, 2, 3])
    :ok
  end

  test "up invokes the repository adapter with up commands" do
    capture_io(fn ->
      assert up(MockRepo, 0, Migration) == :ok
      assert up(MockRepo, 1, Migration) == :already_up
      assert up(MockRepo, 10, ReversibleMigration) == :ok
    end)
  end

  test "down invokes the repository adapter with down commands" do
    capture_io(fn ->
      assert down(MockRepo, 0, Migration) == :already_down
      assert down(MockRepo, 1, Migration) == :ok
      assert down(MockRepo, 2, ReversibleMigration) == :ok
    end)
  end

  test "up raises error when missing up/0 and change/0" do
    assert_raise Ecto.MigrationError, fn ->
      Ecto.Migrator.up(MockRepo, 0, InvalidMigration)
    end
  end

  test "down raises error when missing down/0 and change/0" do
    assert_raise Ecto.MigrationError, fn ->
      Ecto.Migrator.down(MockRepo, 1, InvalidMigration)
    end
  end

  test "expects files starting with an integer" do
    in_tmp fn path ->
      create_migration "a_sample.exs"
      capture_io(fn ->
        assert run(MockRepo, path, :up, all: true) == []
      end)
    end
  end

  test "fails if there is no migration in file" do
    in_tmp fn path ->
      File.write! "13_sample.exs", ":ok"
      assert_raise Ecto.MigrationError, "file 13_sample.exs does not contain any Ecto.Migration", fn ->
        capture_io fn -> run(MockRepo, path, :up, all: true) end
      end
    end
  end

  test "fails if there are duplicated versions" do
    in_tmp fn path ->
      create_migration "13_hello.exs"
      create_migration "13_other.exs"
      assert_raise Ecto.MigrationError, "migrations can't be executed, version 13 is duplicated", fn ->
        capture_io fn -> run(MockRepo, path, :up, all: true) end
      end
    end
  end

  test "upwards migrations skips migrations that are already up" do
    in_tmp fn path ->
      create_migration "1_sample.exs"
      capture_io fn -> assert run(MockRepo, path, :up, all: true) == [] end
    end
  end

  test "downwards migrations skips migrations that are already down" do
    in_tmp fn path ->
      create_migration "1_sample.exs"
      create_migration "4_sample.exs"
      capture_io(fn ->
        assert run(MockRepo, path, :down, all: true) == [1]
      end)
    end
  end

  test "stepwise migrations stop before all have been run" do
    in_tmp fn path ->
      create_migration "13_step_premature_end.exs"
      create_migration "14_step_premature_end.exs"
      capture_io(fn ->
        assert run(MockRepo, path, :up, step: 1) == [13]
      end)
    end
  end

  test "stepwise migrations stop at the number of available migrations" do
    in_tmp fn path ->
      create_migration "13_step_to_the_end.exs"
      create_migration "14_step_to_the_end.exs"
      capture_io(fn ->
        assert run(MockRepo, path, :up, step: 2) == [13, 14]
      end)
    end
  end

  test "stepwise migrations stop even if asked to exceed available" do
    in_tmp fn path ->
      create_migration "13_step_past_the_end.exs"
      create_migration "14_step_past_the_end.exs"
      capture_io(fn ->
        assert run(MockRepo, path, :up, step: 3) == [13, 14]
      end)
    end
  end

  test "version migrations stop before all have been run" do
    in_tmp fn path ->
      create_migration "13_version_premature_end.exs"
      create_migration "14_version_premature_end.exs"
      capture_io(fn ->
        assert run(MockRepo, path, :up, to: 13) == [13]
      end)
    end
  end

  test "version migrations stop at the number of available migrations" do
    in_tmp fn path ->
      create_migration "13_version_to_the_end.exs"
      create_migration "14_version_to_the_end.exs"
      capture_io(fn ->
        assert run(MockRepo, path, :up, to: 14) == [13, 14]
      end)
    end
  end

  test "version migrations stop even if asked to exceed available" do
    in_tmp fn path ->
      create_migration "13_version_past_the_end.exs"
      create_migration "14_version_past_the_end.exs"
      capture_io(fn ->
        assert run(MockRepo, path, :up, to: 15) == [13, 14]
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
