defmodule Mix.Tasks.Ecto.MigrateTest do
  use ExUnit.Case

  import Mix.Tasks.Ecto.Migrate, only: [run: 2]
  import Support.FileHelpers

  migrations_path = Path.join([tmp_path, inspect(Ecto.Migrate), "migrations"])

  setup do
    File.mkdir_p!(unquote(migrations_path))
    :ok
  end

  defmodule Repo do
    def start_link(_) do
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

    def __adapter__ do
      Ecto.TestAdapter
    end

    def config do
      [priv: "tmp/#{inspect(Ecto.Migrate)}", otp_app: :ecto]
    end
  end

  defmodule StartedRepo do
    def start_link(_) do
      Process.put(:already_started, true)
      {:error, {:already_started, :whatever}}
    end

    def stop(_) do
      raise "should not be called"
    end

    def __adapter__ do
      Ecto.TestAdapter
    end

    def config do
      [priv: "tmp/#{inspect(Ecto.Migrate)}", otp_app: :ecto]
    end
  end

  test "runs the migrator with app_repo config" do
    Application.put_env(:ecto, :app_repo, Repo)
    run ["--no-start"], fn _, _, _, _ ->
      Process.put(:migrated, true)
      []
    end
    assert Process.get(:migrated)
    assert Process.get(:started)
  after
    Application.delete_env(:ecto, :app_repo)
  end

  test "runs the migrator after starting repo" do
    run ["-r", to_string(Repo), "--no-start"], fn _, _, _, _ ->
      Process.put(:migrated, true)
      []
    end
    assert Process.get(:migrated)
    assert Process.get(:started)
  end

  test "runs the migrator with the already started repo" do
    run ["-r", to_string(StartedRepo), "--no-start"], fn _, _, _, _ ->
      Process.put(:migrated, true)
      []
    end
    assert Process.get(:migrated)
    assert Process.get(:already_started)
  end

  test "runs the migrator with two repos" do
    run ["-r", to_string(Repo), "-r", to_string(StartedRepo), "--no-start"], fn _, _, _, _ ->
      Process.put(:migrated, true)
      []
    end
    assert Process.get(:migrated)
    assert Process.get(:started)
    assert Process.get(:already_started)
  end

  test "runs the migrator yielding the repository and migrations path" do
    run ["-r", to_string(Repo), "--quiet", "--prefix", "foo"], fn repo, path, direction, opts ->
      assert repo == Repo
      assert path == Application.app_dir(:ecto, "tmp/#{inspect(Ecto.Migrate)}/migrations")
      assert direction == :up
      assert opts[:all] == true
      assert opts[:log] == false
      assert opts[:prefix] == "foo"
      []
    end
    assert Process.get(:started)
  end

  test "raises when migrations path does not exist" do
    File.rm_rf!(unquote(migrations_path))
    assert_raise Mix.Error, fn ->
      run ["-r", to_string(Repo)], fn _, _, _, _ -> [] end
    end
    assert !Process.get(:started)
  end
end
