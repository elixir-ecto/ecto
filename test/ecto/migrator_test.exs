defmodule Ecto.MigratorTest do
  use ExUnit.Case

  import Support.FileHelpers

  defmodule ProcessRepo do
    @behaviour Ecto.Adapter.Migrations

    def adapter do
      __MODULE__
    end

    def insert_migration_version(__MODULE__, _version), do: nil
    def delete_migration_version(__MODULE__, _version), do: nil
    def check_migration_version(__MODULE__, _version),  do: nil
    def execute_migration(__MODULE__, _command),        do: nil

    def migrated_versions(__MODULE__) do
      Process.get(:migrated_versions)
    end

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

  defmodule MockRunner do
    use GenServer.Behaviour

    def start_link do
      :gen_server.start_link({:local, :migration_runner}, __MODULE__, [], [])
    end

    def handle_call({:direction, direction}, _from, state) do
      {:reply, {:changed, direction}, state}
    end

    def handle_call({:execute, command}, _from, state) do
      {:reply, {:executed, command}, state}
    end
  end

  setup_all do
    {:ok, pid} = MockRunner.start_link
    {:ok, pid: pid}
  end

  teardown_all context do
    :erlang.exit(context[:pid], :kill)
    :ok
  end

  setup do
    Process.put(:migrated_versions, [1, 2, 3])
    :ok
  end

  test "up invokes the repository adapter with up commands" do
    assert Ecto.Migrator.up(ProcessRepo, 0, Migration) == :ok
  end

  test "down invokes the repository adapter with down commands" do
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
