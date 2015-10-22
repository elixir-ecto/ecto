defmodule Mix.Tasks.Ecto.RollbackTest do
  use ExUnit.Case, async: true

  import Mix.Tasks.Ecto.Rollback, only: [run: 2]

  defmodule Repo do
    def start_link do
      Process.put(:started, true)
      Task.start_link fn ->
        Process.flag(:trap_exit, true)
        receive do
          {:EXIT, _, :normal} -> :ok
        end
      end
    end

    def stop(_pid) do
      :ok
    end

    def __repo__ do
      true
    end

    def config do
      [priv: "hello", otp_app: :ecto]
    end
  end

  defmodule StartedRepo do
    def start_link do
      {:error, {:already_started, :whatever}}
    end

    def stop(_) do
      raise "I should never be called"
    end

    def __repo__ do
      true
    end

    def config do
      [priv: "hello", otp_app: :ecto]
    end
  end

  test "runs the migrator after starting repo" do
    run ["-r", to_string(Repo), "--no-start"], fn _, _, _, _ ->
      Process.put(:migrated, true)
    end
    assert Process.get(:migrated)
    assert Process.get(:started)
  end

  test "runs the migrator with already started repo" do
    run ["-r", to_string(StartedRepo), "--no-start"], fn _, _, _, _ ->
      Process.put(:migrated, true)
    end
    assert Process.get(:migrated)
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
