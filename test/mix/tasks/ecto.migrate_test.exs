defmodule Mix.Tasks.Ecto.MigrateTest do
  use ExUnit.Case

  import Mix.Tasks.Ecto.Migrate, only: [run: 2]
  import Support.FileHelpers

  @migrations_path Path.join([tmp_path(), inspect(Ecto.Migrate), "migrations"])

  setup do
    File.mkdir_p!(@migrations_path)
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

    def stop do
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

    def stop do
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
    Application.put_env(:ecto, :ecto_repos, [Repo])
    run ["--no-start"], fn _, _, _ ->
      Process.put(:migrated, true)
      []
    end
    assert Process.get(:migrated)
    assert Process.get(:started)
  after
    Application.delete_env(:ecto, :ecto_repos)
  end

  test "runs the migrator after starting repo" do
    run ["-r", to_string(Repo), "--no-start"], fn _, _, _ ->
      Process.put(:migrated, true)
      []
    end
    assert Process.get(:migrated)
    assert Process.get(:started)
  end

  test "runs the migrator with the already started repo" do
    run ["-r", to_string(StartedRepo), "--no-start"], fn _, _, _ ->
      Process.put(:migrated, true)
      []
    end
    assert Process.get(:migrated)
    assert Process.get(:already_started)
  end

  test "runs the migrator with two repos" do
    run ["-r", to_string(Repo), "-r", to_string(StartedRepo), "--no-start"], fn _, _, _ ->
      Process.put(:migrated, true)
      []
    end
    assert Process.get(:migrated)
    assert Process.get(:started)
    assert Process.get(:already_started)
  end

  test "runs the migrator yielding the repository and migrations path" do
    run ["-r", to_string(Repo), "--quiet", "--prefix", "foo"], fn repo, direction, opts ->
      assert repo == Repo
      assert direction == :up
      assert opts[:all] == true
      assert opts[:log] == false
      assert opts[:prefix] == "foo"
      []
    end
    assert Process.get(:started)
  end

  test "raises when migrations path does not exist" do
    File.rm_rf!(@migrations_path)
    assert_raise Mix.Error, fn ->
      run ["-r", to_string(Repo)], fn _, _, _ -> [] end
    end
    assert !Process.get(:started)
  end
end
