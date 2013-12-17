defmodule Mix.Tasks.Ecto.MigrateTest do
  use ExUnit.Case, async: true

  import Mix.Tasks.Ecto.Migrate, only: [run: 2]

  defmodule Repo do
    def start_link do
      Process.put(:started, true)
      :ok
    end

    def priv do
      "hello"
    end

    def __repo__ do
      true
    end
  end

  teardown_all do
    :erlang.exit(:erlang.whereis(:migration_runner), :kill)
    :ok
  end

  test "runs the migrator" do
    run [to_string(Repo)], fn _, _ ->
      Process.put(:migrated, true)
    end
    assert Process.get(:migrated)
    assert Process.get(:started)
  end

  test "runs the migrator yielding the repository and migrations path" do
    run [to_string(Repo)], fn repo, path ->
      assert repo == Repo
      assert path == "hello/migrations"
    end
  end
end
