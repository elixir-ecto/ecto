defmodule Mix.Tasks.Ecto.Gen.ModelTest do
  use ExUnit.Case, async: false

  import Support.FileHelpers
  import Mix.Tasks.Ecto.Gen.Model, only: [run: 1]

  build_path = Path.join(build_tmp_path, inspect(Ecto.Gen.Model))
  tmp_path   = Path.join(tmp_path, inspect(Ecto.Gen.Model))
  @migrations_path Path.join(build_path, "migrations")

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
    File.rm_rf!(unquote(build_path))
    :ok
  end

  test "generates an entity file" do
    in_tmp fn _ ->
      run [to_string(Repo), "MyModel", "name:string", "created_at:datetime"]
      assert_file "lib/my_model.ex"
    end
  end

  test "generates an test file" do
    in_tmp fn _ ->
      run [to_string(Repo), "MyModel", "name:string", "created_at:datetime"]
      assert_file "test/my_model_test.exs"
    end
  end

  test "generates a migration file" do
    in_tmp fn _ ->
      run [to_string(Repo), "MyModel", "name:string", "created_at:datetime"]
    end
    assert [name] = File.ls! @migrations_path
    assert name =~ %r/^\d{14}_create_my_model_table\.exs$/
  end

end
