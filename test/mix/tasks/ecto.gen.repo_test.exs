defmodule Mix.Tasks.Ecto.Gen.RepoTest do
  use ExUnit.Case

  import Support.FileHelpers
  import Mix.Tasks.Ecto.Gen.Repo, only: [run: 1]

  test "generates a new repo" do
    in_tmp fn _ ->
      run ["Repo"]

      assert_file "lib/repo.ex", fn file ->
        assert String.contains? file, "defmodule Repo do"
        assert String.contains? file, "use Ecto.Repo"
        assert String.contains? file, "adapter: Ecto.Adapters.Postgres,"
        assert String.contains? file, "otp_app: :ecto"
      end

      assert_file "config/config.exs", """
      use Mix.Config

      config :ecto, Repo,
        database: "ecto_repo",
        username: "user",
        password: "pass",
        hostname: "localhost"
      """

      run ["AnotherRepo"]

      assert_file "config/config.exs", """
      config :ecto, AnotherRepo,
        database: "ecto_another_repo",
        username: "user",
        password: "pass",
        hostname: "localhost"
      """
    end
  end

  test "generates a new namespaced repo" do
    in_tmp fn _ ->
      run ["My.AppRepo"]
      assert_file "lib/my/app_repo.ex", "defmodule My.AppRepo do"
    end
  end

  test "raises when missing repo" do
    assert_raise Mix.Error, fn -> run [] end
  end
end
