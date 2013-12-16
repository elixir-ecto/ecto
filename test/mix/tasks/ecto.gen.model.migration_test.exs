defmodule Mix.Tasks.Ecto.Gen.Model.MigrationTest do
  use ExUnit.Case, async: false

  import Support.FileHelpers
  import Mix.Tasks.Ecto.Gen.Model.Migration, only: [run: 1]

  build_path = Path.join(build_tmp_path, inspect(Ecto.Gen.Model.Migration))
  tmp_path   = Path.join(tmp_path, inspect(Ecto.Gen.Model.Migration))
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
      assert file =~ "defmodule Mix.Tasks.Ecto.Gen.Model.MigrationTest.Repo.Migrations.CreateMyModelTable do"
      assert file =~ "use Ecto.Migration"
      assert file =~ "def up do"
      assert file =~ "CREATE TABLE IF NOT EXISTS repo_my_model ("
      assert file =~ "id serial primary key,"
      assert file =~ "name text,"
      assert file =~ "created_at timestamp"
      assert file =~ ");"
      assert file =~ "def down do"
      assert file =~ "DROP TABLE repo_my_model;"
    end
  end

  test "generates a new namespaced migration" do
    run [to_string(Repo), "My.SpecialModel", "greeting:string", "counter:integer"]
    assert [name] = File.ls!(@migrations_path)
    assert name =~ %r/^\d{14}_create_my_special_model_table\.exs$/
    assert_file Path.join(@migrations_path, name), fn file ->
      assert file =~ "defmodule Mix.Tasks.Ecto.Gen.Model.MigrationTest.Repo.Migrations.CreateMySpecialModelTable do"
      assert file =~ "use Ecto.Migration"
      assert file =~ "def up do"
      assert file =~ "CREATE TABLE IF NOT EXISTS repo_my_special_model ("
      assert file =~ "id serial primary key,"
      assert file =~ "greeting text,"
      assert file =~ "counter integer"
      assert file =~ ");"
      assert file =~ "def down do"
      assert file =~ "DROP TABLE repo_my_special_model;"
    end
  end

  test "ignores virtual fields in the table" do
    run [to_string(Repo), "MyModel", "name:string", "magic:virtual"]
    assert [name] = File.ls!(@migrations_path)
    assert_file Path.join(@migrations_path, name), fn file ->
      assert file =~ "name text"
      refute file =~ "magic"
    end
  end

  test "keeps a field named \"virtual\"" do
    run [to_string(Repo), "MyModel", "name:string", "virtual:text"]
    assert [name] = File.ls!(@migrations_path)
    assert_file Path.join(@migrations_path, name), fn file ->
      assert file =~ "name text"
      assert file =~ "virtual text"
    end
  end

  test "raises when missing file" do
    assert_raise Mix.Error, fn -> run [to_string(Repo)] end
  end
end
