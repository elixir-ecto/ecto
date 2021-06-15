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

    test "opens __FILE__ and __LINE__" do
      System.put_env("ECTO_EDITOR", "echo foo __FILE__:__LINE__")

      open?("lib/some/file.ex", 4)
      assert_received {:mix_shell, :run, ["foo lib/some/file.ex:4\n"]}
    after
      System.put_env("ECTO_EDITOR", @editor)
    end

    test "opens without __FILE__ and __LINE__" do
      System.put_env("ECTO_EDITOR", "echo foo")

      open?("lib/some/file.ex", 4)
      assert_received {:mix_shell, :run, ["foo lib/some/file.ex:4\n"]}
    after
      System.put_env("ECTO_EDITOR", @editor)
    end
  end
end
