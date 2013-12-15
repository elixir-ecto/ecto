defmodule Mix.Tasks.Ecto.Gen.MigrationTest do
  use ExUnit.Case, async: false

  import Support.FileHelpers
  import Mix.Tasks.Ecto.Gen.Migration, only: [run: 1]

  build_path = Path.join(build_tmp_path, inspect(Ecto.Gen.Migration))
  tmp_path   = Path.join(tmp_path, inspect(Ecto.Gen.Migration))
  @migrations_path Path.join(tmp_path, "migrations")

  defmodule Repo do
    def priv do
      unquote(build_path)
    end

    def __repo__ do
      true
    end
  end

  setup do
    File.rm_rf!(unquote(tmp_path))
    :ok
  end

  test "generates a new migration" do
    run [to_string(Repo), "my_migration"]
    assert [name] = File.ls!(@migrations_path)
    assert name =~ %r/^\d{14}_my_migration\.exs$/
    assert_file Path.join(@migrations_path, name), fn file ->
      assert file =~ "defmodule Mix.Tasks.Ecto.Gen.MigrationTest.Repo.Migrations.MyMigration do"
      assert file =~ "use Ecto.Migration"
      assert file =~ "def up do"
      assert file =~ "def down do"
    end
  end

  test "raises when missing file" do
    assert_raise Mix.Error, fn -> run [to_string(Repo)] end
  end
end
