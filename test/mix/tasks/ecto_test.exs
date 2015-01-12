defmodule Mix.EctoTest do
  use ExUnit.Case, async: true

  import Mix.Ecto

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

  test :parse_repo do
    assert parse_repo([Repo]) == {Repo, []}
    assert parse_repo([Repo, "foo"]) == {Repo, ["foo"]}
    assert parse_repo([inspect(Repo), "foo"]) == {Repo, ["foo"]}
    assert parse_repo([to_string(Repo), "foo"]) == {Repo, ["foo"]}
    assert_raise Mix.Error, fn -> parse_repo([]) end
    assert_raise Mix.Error, fn -> parse_repo([""]) end
  end

  test :ensure_repo do
    assert ensure_repo(Repo) == Repo
    assert_raise Mix.Error, fn -> parse_repo(String) end
    assert_raise Mix.Error, fn -> parse_repo(NotLoaded) end
  end

  test :ensure_started do
    Process.put(:start_link, :ok)
    assert ensure_started(Repo) == Repo

    Process.put(:start_link, {:ok, self})
    assert ensure_started(Repo) == Repo

    Process.put(:start_link, {:error, {:already_started, self}})
    assert ensure_started(Repo) == Repo

    Process.put(:start_link, {:error, self})
    assert_raise Mix.Error, fn -> ensure_started(Repo) end
  end

  test :migrations_path do
    Process.put(:priv, nil)
    assert migrations_path(Repo) == Application.app_dir(:ecto, "priv/repo/migrations")
    Process.put(:priv, "hello")
    assert migrations_path(Repo) == Application.app_dir(:ecto, "hello/migrations")
  end
end
