defmodule Mix.Tasks.Ecto.Gen.MigrationTest do
  use ExUnit.Case, async: true

  import Support.FileHelpers
  import Mix.Tasks.Ecto.Gen.Migration, only: [run: 1]

  tmp_path = Path.join(tmp_path, inspect(Ecto.Gen.Migration))
  @migrations_path Path.join(tmp_path, "migrations")

  defmodule Repo do
    def __repo__ do
      true
    end

    def config do
      [priv: "tmp/#{inspect(Ecto.Gen.Migration)}", otp_app: :ecto]
    end
  end

  setup do
    File.rm_rf!(unquote(tmp_path))
    :ok
  end

  test "generates a new migration" do
    run ["-r", to_string(Repo), "my_migration"]
    assert [name] = File.ls!(@migrations_path)
    assert String.match? name, ~r/^\d{14}_my_migration\.exs$/
    assert_file Path.join(@migrations_path, name), fn file ->
      assert file =~ "defmodule Mix.Tasks.Ecto.Gen.MigrationTest.Repo.Migrations.MyMigration do"
      assert file =~ "use Ecto.Migration"
      assert file =~ "def change do"
    end
  end

  test "underscores the filename when generating a migration" do
    run ["-r", to_string(Repo), "MyMigration"]
    assert [name] = File.ls!(@migrations_path)
    assert String.match? name, ~r/^\d{14}_my_migration\.exs$/
  end

  test "raises when missing file" do
    assert_raise Mix.Error, fn -> run ["-r", to_string(Repo)] end
  end
end
