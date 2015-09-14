defmodule Mix.EctoTest do
  use ExUnit.Case, async: true
  import Mix.Ecto

  test "parse repo" do
    assert parse_repo(["-r", "Repo"]) == [Repo]
    assert parse_repo(["--repo", Repo]) == [Repo]
    assert parse_repo([]) == [Ecto.Repo]

    assert parse_repo(["-r", "Repo", "-r", "Repo2"]) == [Repo, Repo2]
    assert parse_repo(["-r", "Repo", "--quiet"]) == [Repo]
    assert parse_repo(["-r", "Repo", "-r", "Repo2", "--quiet"]), [Repo, Repo2]

    Application.put_env(:ecto, :app_namespace, Foo)
    assert parse_repo([]) == [Foo.Repo]
  after
    Application.delete_env(:ecto, :app_namespace)
  end

  defmodule Repo do
    def start_link do
      Process.get(:start_link)
    end

    def __repo__ do
      true
    end

    def config do
      [priv: Process.get(:priv), otp_app: :ecto]
    end
  end

  defmodule Repo2 do
    def start_link do
    end

    def __repo__ do
      true
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

  test "ensure started" do
    Process.put(:start_link, {:ok, self})
    assert ensure_started(Repo) == {:ok, self}

    Process.put(:start_link, {:error, {:already_started, self}})
    assert ensure_started(Repo) == {:ok, nil}

    Process.put(:start_link, {:error, self})
    assert_raise Mix.Error, fn -> ensure_started(Repo) end
  end

  test "migrations path" do
    Process.put(:priv, nil)
    assert migrations_path(Repo) == Application.app_dir(:ecto, "priv/repo/migrations")
    Process.put(:priv, "hello")
    assert migrations_path(Repo) == Application.app_dir(:ecto, "hello/migrations")
  end
end
