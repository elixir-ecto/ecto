defmodule Mix.EctoTest do
  use ExUnit.Case, async: true
  import Mix.Ecto

  test "parse repo" do
    assert parse_repo(["-r", "Repo"]) == [Repo]
    assert parse_repo(["--repo", Repo]) == [Repo]
    assert parse_repo(["-r", "Repo", "-r", "Repo2"]) == [Repo, Repo2]
    assert parse_repo(["-r", "Repo", "--quiet"]) == [Repo]
    assert parse_repo(["-r", "Repo", "-r", "Repo2", "--quiet"]), [Repo, Repo2]

    # Warning
    assert parse_repo([]) == []

    # No warning
    Application.put_env(:ecto, :ecto_repos, [Foo.Repo])
    assert parse_repo([]) == [Foo.Repo]
  after
    Application.delete_env(:ecto, :ecto_repos)
  end

  defmodule Repo do
    def __adapter__ do
      Ecto.TestAdapter
    end

    def config do
      [priv: Process.get(:priv), otp_app: :ecto]
    end
  end

  test "ensure repo" do
    assert ensure_repo(Repo, []) == Repo
    assert_raise Mix.Error, fn -> ensure_repo(String, []) end
    assert_raise Mix.Error, fn -> ensure_repo(NotLoaded, []) end
  end

  describe "open?/2" do
    @editor System.get_env("ECTO_EDITOR")

    test "opens __FILE__ and __LINE__", ctx do
      System.put_env("ECTO_EDITOR", "echo -n __LINE__:__FILE__ > output.txt")

      in_tmp(ctx.test, fn ->
        open?("lib/some/file.ex", 4)

        assert File.read!("output.txt") == "4:lib/some/file.ex"
      end)
    after
      System.put_env("ECTO_EDITOR", @editor)
    end
  end

  @tmp_path Path.expand("../../tmp", __DIR__)

  defp in_tmp(path, fun) do
    path = Path.join(@tmp_path, to_string(path))

    try do
      File.rm_rf!(path)
      File.mkdir_p!(path)
      File.cd!(path, fun)
    after
      File.rm_rf!(path)
    end
  end
end
