defmodule Mix.Tasks.Ecto.RollbackTest do
  use ExUnit.Case, async: true

  import Mix.Tasks.Ecto.Rollback, only: [run: 2]

  defmodule Repo do
    def start_link do
      Process.put(:started, true)
      Task.start_link fn -> :timer.sleep(:infinity) end
    end

    def __repo__ do
      true
    end

    def config do
      [priv: "hello", otp_app: :ecto]
    end
  end

  test "runs the migrator with the repo started" do
    run ["-r", to_string(Repo), "--no-start"], fn _, _, _, _ ->
      Process.put(:migrated, true)
    end
    assert Process.get(:migrated)
    assert Process.get(:started)
  end

  test "runs the migrator yielding the repository and migrations path" do
    run ["-r", to_string(Repo)], fn repo, path, direction, strategy ->
      assert repo == Repo
      assert path == Application.app_dir(:ecto, "hello/migrations")
      assert direction == :down
      assert strategy[:step] == 1
    end
    assert Process.get(:started)
  end
end
