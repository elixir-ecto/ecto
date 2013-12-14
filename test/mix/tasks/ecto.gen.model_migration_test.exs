defmodule Mix.Tasks.Ecto.Gen.ModelMigrationTest do
  use ExUnit.Case, async: true

  import Support.FileHelpers
  import Mix.Tasks.Ecto.Gen.ModelMigration, only: [run: 1]

  build_path = Path.join(build_tmp_path, inspect(Ecto.Gen.ModelMigration))
  tmp_path   = Path.join(tmp_path, inspect(Ecto.Gen.ModelMigration))
  @migrations_path Path.join(tmp_path, "migrations")

  defmodule Repo do
    use Ecto.Repo, adapter: Ecto.Adapters.Postgres

    def url do
      "ecto://postgres:postgres@localhost/repo"
    end

    def priv do
      unquote(build_path)
    end
  end

  setup do
    File.rm_rf!(unquote(tmp_path))
    :ok
  end

  test "generates a new migration" do
    run [to_string(Repo), "MyModel", "name:string", "created_at:datetime"]
    assert [name] = File.ls!(@migrations_path)
    assert name =~ %r/^\d{14}_create_my_model_table\.exs$/
    assert_file Path.join(@migrations_path, name), fn file ->
      assert file =~ "defmodule Mix.Tasks.Ecto.Gen.ModelMigrationTest.Repo.Migrations.CreateMyModelTable do"
      assert file =~ "use Ecto.Migration"
      assert file =~ "def up do"
      assert file =~ "CREATE TABLE repo_my_model ("
      assert file =~ "id serial primary key,"
      assert file =~ "name text,"
      assert file =~ "created_at timestamp"
      assert file =~ ");"
      assert file =~ "def down do"
      assert file =~ "DROP TABLE repo_my_model;"
    end
  end

  test "raises when missing file" do
    assert_raise Mix.Error, fn -> run [to_string(Repo)] end
  end
end
