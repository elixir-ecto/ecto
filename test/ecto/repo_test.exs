Code.require_file "../test_helper.exs", __DIR__

defmodule Ecto.Adapter.Test do
  def default_port, do: 54321
end

defmodule Ecto.RepoTest do
  use ExUnit.Case, async: true

  alias Ecto.Repo

  test "parse url" do
    assert Repo.parse_url("ecto+postgres://eric:hunter2@host:12345/mydb?size=10&a=b") == [
           adapter: Ecto.Adapter.Postgres,
           username: "eric",
           password: "hunter2",
           hostname: "host",
           database: "mydb",
           port: 12345,
           opts: HashDict.new([{ "size", "10" }, { "a", "b" }]) ]
  end

  test "parse invalid url" do
    assert_raise Ecto.InvalidURL, %r"not an ecto url", fn ->
      Repo.parse_url("http://eric:hunter2@host:123/mydb")
    end

    assert_raise Ecto.InvalidURL, %r"url has to contain username and password", fn ->
      Repo.parse_url("ecto+postgres://eric@host:123/mydb")
    end

    assert_raise Ecto.InvalidURL, %r"path should be a database name", fn ->
      Repo.parse_url("ecto+postgres://eric:hunter2@host:123/a/b/c")
    end

    assert_raise Ecto.InvalidURL, %r"path should be a database name", fn ->
      Repo.parse_url("ecto+postgres://eric:hunter2@host:123/")
    end
  end

  test "default port" do
    settings = Repo.parse_url("ecto+test://eric:hunter2@host/mydb")
    assert settings[:port] == 54321
  end
end
