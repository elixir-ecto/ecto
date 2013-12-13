defmodule Mix.Tasks.Ecto.RollbackTest do
  use ExUnit.Case, async: true

  import Mix.Tasks.Ecto.Rollback, only: [run: 2]

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

  test "runs the migrator" do
    run [to_string(Repo)], fn _, _, _ ->
      Process.put(:migrated, true)
    end
    assert Process.get(:migrated)
    assert Process.get(:started)
  end

  test "runs the migrator yielding the repository and migrations path" do
    run [to_string(Repo)], fn repo, path, opts ->
      assert repo == Repo
      assert path == "hello/migrations"
      assert opts == [direction: :down]
    end
  end
end
