Code.require_file "../test_helper.exs", __DIR__

defmodule Ecto.Adapter.Test do
  def default_port, do: 54321
end

defmodule Ecto.RepoTest do
  use ExUnit.Case, async: true

  alias Ecto.Repo

  test "parse url" do
    assert Repo.parse_url("ecto://eric:hunter2@host:12345/mydb?size=10&a=b", 0) == [
           password: "hunter2",
           username: "eric",
           hostname: "host",
           database: "mydb",
           port: 12345,
           size: "10",
           a: "b" ]
  end

  test "parse invalid url" do
    assert_raise Ecto.InvalidURL, %r"not an ecto url", fn ->
      Repo.parse_url("http://eric:hunter2@host:123/mydb", 0)
    end

    assert_raise Ecto.InvalidURL, %r"url has to contain a username", fn ->
      Repo.parse_url("ecto://host:123/mydb", 0)
    end

    assert_raise Ecto.InvalidURL, %r"path should be a database name", fn ->
      Repo.parse_url("ecto://eric:hunter2@host:123/a/b/c", 0)
    end

    assert_raise Ecto.InvalidURL, %r"path should be a database name", fn ->
      Repo.parse_url("ecto://eric:hunter2@host:123/", 0)
    end
  end

  test "default port" do
    settings = Repo.parse_url("ecto://eric:hunter2@host/mydb", 54321)
    assert settings[:port] == 54321
  end

  test "optional password" do
    url = Repo.parse_url("ecto://eric@host:123/mydb", 0)
    refute url[:password]
  end
end
