defmodule Mix.Tasks.Ecto.Gen.RepoTest do
  use ExUnit.Case

  import Mix.Tasks.Ecto.Gen.Repo, only: [run: 1]

  test "raises when no repo given" do
    msg = "ecto.gen.repo expects the repository to be given as -r MyApp.Repo"
    assert_raise Mix.Error, msg, fn -> run [] end
  end

  test "raises when multiple repos given" do
    msg = "ecto.gen.repo expects a single repository to be given"
    assert_raise Mix.Error, msg, fn -> run ["-r", "Foo.Repo", "--repo", "Bar.Repo"] end
  end

  test "generates a new repo" do
    in_tmp "new_repo", fn ->
      run ["-r", "Repo"]

      assert_file "lib/repo.ex", """
      defmodule Repo do
        use Ecto.Repo,
          otp_app: :ecto,
          adapter: Ecto.Adapters.Postgres
      end
      """

      assert_file "config/config.exs", """
      import Config

      config :ecto, Repo,
        database: "ecto_repo",
        username: "user",
        password: "pass",
        hostname: "localhost"
      """
    end
  end

  test "generates a new repo with existing config file" do
    in_tmp "existing_config", fn ->
      File.mkdir_p! "config"
      File.write! "config/config.exs", """
      # Hello
      use Mix.Config
      # World
      """

      run ["-r", "Repo"]

      assert_file "config/config.exs", """
      # Hello
      use Mix.Config

      config :ecto, Repo,
        database: "ecto_repo",
        username: "user",
        password: "pass",
        hostname: "localhost"
      # World
      """
    end
  end

  test "generates a new namespaced repo" do
    in_tmp "namespaced", fn ->
      run ["-r", "My.AppRepo"]
      assert_file "lib/my/app_repo.ex", "defmodule My.AppRepo do"
    end
  end

  @tmp_path Path.expand("../../../tmp", __DIR__)

  defp in_tmp(path, fun) do
    path = Path.join(@tmp_path, path)
    File.rm_rf!(path)
    File.mkdir_p!(path)
    File.cd!(path, fun)
  end

  defp assert_file(file, match) do
    assert File.read!(file) =~ match
  end
end
