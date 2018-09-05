defmodule Mix.Tasks.Ecto.MigrationsTest do
  use ExUnit.Case

  import Mix.Tasks.Ecto.Migrations, only: [run: 3]
  import Support.FileHelpers

  migrations_path = Path.join([tmp_path(), inspect(Ecto.Migrations), "migrations"])

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
      [priv: "tmp/#{inspect(Ecto.Migrations)}", otp_app: :ecto]
    end
  end


  test "migrations displays the up and down status for the default repo" do
    Application.put_env(:ecto, :ecto_repos, [Repo])

    migrations = fn _ ->
      [
        {:up,   0,              "up_migration_0"},
        {:up,   20160000000001, "up_migration_1"},
        {:up,   20160000000002, "up_migration_2"},
        {:up,   20160000000003, "up_migration_3"},
        {:down, 20160000000004, "down_migration_1"},
        {:down, 20160000000005, "down_migration_2"}
      ]
    end

    expected_output = """

      Repo: Mix.Tasks.Ecto.MigrationsTest.Repo

        Status    Migration ID    Migration Name
      --------------------------------------------------
        up        0               up_migration_0
        up        20160000000001  up_migration_1
        up        20160000000002  up_migration_2
        up        20160000000003  up_migration_3
        down      20160000000004  down_migration_1
        down      20160000000005  down_migration_2
      """
    run [], migrations, fn i -> assert(i == expected_output) end
  end

  test "migrations displays the up and down status for any given repo" do
    migrations = fn _ ->
      [
        {:up,   20160000000001, "up_migration_1"},
        {:down, 20160000000002, "down_migration_1"}
      ]
    end

    expected_output = """

      Repo: Mix.Tasks.Ecto.MigrationsTest.Repo

        Status    Migration ID    Migration Name
      --------------------------------------------------
        up        20160000000001  up_migration_1
        down      20160000000002  down_migration_1
      """

    run ["-r", to_string(Repo)], migrations, fn i -> assert(i == expected_output) end
  end
end
