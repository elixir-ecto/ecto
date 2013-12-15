defmodule Mix.Tasks.Ecto.Gen.Model.EntityTest do
  use ExUnit.Case, async: false

  import Support.FileHelpers
  import Mix.Tasks.Ecto.Gen.Model.Entity, only: [run: 1]

  defmodule Repo do
    use Ecto.Repo, adapter: Ecto.Adapters.Postgres

    def url do
      "ecto://postgres:postgres@localhost/repo"
    end
  end

  setup do
    File.rm_rf!(unquote(tmp_path))
    :ok
  end

  test "generates a new entity" do
    in_tmp fn _ ->
      run [to_string(Repo), "MyModel", "name:string", "created_at:datetime"]
      assert_file "lib/my_model.ex", fn file ->
        assert file =~ "defmodule MyModel.Entity do"
        assert file =~ "use Ecto.Entity"
        assert file =~ "field :name, :string"
        assert file =~ "field :created_at, :datetime"
        assert file =~ "defmodule MyModel do"
        assert file =~ "use Ecto.Model"
        assert file =~ "queryable \"repo_my_model\", MyModel.Entity"
      end
    end
  end

  test "generates a new namespaced model" do
    in_tmp fn _ ->
      run [to_string(Repo), "My.SpecialModel", "greeting:string", "counter:integer"]

      assert_file "lib/my/special_model.ex", fn file ->
        assert file =~ "defmodule My.SpecialModel.Entity do"
        assert file =~ "use Ecto.Entity"
        assert file =~ "field :greeting, :string"
        assert file =~ "field :counter, :integer"
        assert file =~ "defmodule My.SpecialModel do"
        assert file =~ "use Ecto.Model"
        assert file =~ "queryable \"repo_my_special_model\", My.SpecialModel.Entity"
      end
    end
  end

  test "raises when missing file" do
    assert_raise Mix.Error, fn -> run [to_string(Repo)] end
  end

  test "generates an entity test" do
    in_tmp fn _ ->
      run [to_string(Repo), "MyModel", "name:string", "created_at:datetime"]

      assert_file "test/my_model_test.exs", fn file ->
        assert file =~ "defmodule MyModelTest do"
        assert file =~ "test \"the truth\" do"
      end
    end
  end

  test "generates a namespaced entity test" do
    in_tmp fn _ ->
      run [to_string(Repo), "My.SpecialModel", "greeting:string", "counter:integer"]

      assert_file "test/my/special_model_test.exs", fn file ->
        assert file =~ "defmodule My.SpecialModelTest do"
        assert file =~ "test \"the truth\" do"
      end
    end
  end

end
