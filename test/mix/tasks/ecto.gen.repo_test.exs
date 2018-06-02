defmodule Mix.Tasks.Ecto.Gen.RepoTest do
  use ExUnit.Case

  import Support.FileHelpers
  import Mix.Tasks.Ecto.Gen.Repo, only: [run: 1]

  test "generates a new repo" do
    in_tmp fn _ ->
      run ["-r", "Repo"]

      assert_file "lib/repo.ex", """
      defmodule Repo do
        use Ecto.Repo,
          otp_app: :ecto,
          adapter: Ecto.Adapters.Postgres
      end
      """

      assert_file "config/config.exs", """
      use Mix.Config

      config :ecto, Repo,
        database: "ecto_repo",
        username: "user",
        password: "pass",
        hostname: "localhost"
      """
    end
  end

  test "generates a new repo with existing config file" do
    in_tmp fn _ ->
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
    in_tmp fn _ ->
      run ["-r", "My.AppRepo"]
      assert_file "lib/my/app_repo.ex", "defmodule My.AppRepo do"
    end
  end
end
