defmodule Mix.Tasks.Ecto.Gen.RepoTest do
  use Ecto.TestCase
  import Mix.Tasks.Ecto.Gen.Repo, only: [run: 1]

  test "generates a new repo" do
    in_tmp fn _ ->
      run ["Repo"]

      assert_file "lib/repo.ex", fn file ->
        assert file =~ "defmodule Repo do"
        assert file =~ "use Ecto.Repo, adapter: Ecto.Adapters.Postgres"
        assert file =~ "app_dir(:ecto, \"priv/repo\")"
        assert file =~ "\"ecto://postgres:postgres@localhost/ecto_repo\""
      end
    end
  end

  test "generates a new namespaced repo" do
    in_tmp fn _ ->
      run ["My.AppRepo"]

      assert_file "lib/my/app_repo.ex", fn file ->
        assert file =~ "defmodule My.AppRepo do"
        assert file =~ "use Ecto.Repo, adapter: Ecto.Adapters.Postgres"
        assert file =~ "app_dir(:ecto, \"priv/app_repo\")"
        assert file =~ "\"ecto://postgres:postgres@localhost/ecto_app_repo\""
      end
    end
  end

  test "raises when missing repo" do
    assert_raise Mix.Error, fn -> run [] end
  end
end
