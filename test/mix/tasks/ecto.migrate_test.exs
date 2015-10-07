defmodule Mix.Tasks.Ecto.MigrateTest do
  use ExUnit.Case, async: true

  import Mix.Tasks.Ecto.Migrate, only: [run: 2]

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

    def __adapter__ do
      Ecto.Adapters.Postgres
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
    run ["-r", to_string(Repo), "--quiet"], fn repo, path, direction, opts ->
      assert repo == Repo
      assert path == Application.app_dir(:ecto, "hello/migrations")
      assert direction == :up
      assert opts[:all] == true
      assert opts[:log] == false
    end
    assert Process.get(:started)
  end
end
