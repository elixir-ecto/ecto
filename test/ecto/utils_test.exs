defmodule Ecto.UtilsTest do
  use ExUnit.Case, async: true

  import Ecto.Utils

  test "parse_url options" do
    url = parse_url("ecto://eric:hunter2@host:12345/mydb?size=10&a=b")
    assert {:password, "hunter2"} in url
    assert {:username, "eric"} in url
    assert {:hostname, "host"} in url
    assert {:database, "mydb"} in url
    assert {:port, 12345} in url
    assert {:size, "10"} in url
    assert {:a, "b"} in url
  end

  test "parse_urls empty username/password" do
    url = parse_url("ecto://host:12345/mydb?size=10&a=b")
    assert !Dict.has_key?(url, :username)
    assert !Dict.has_key?(url, :password)
  end

  test "fail on invalid urls" do
    assert_raise Ecto.InvalidURL, ~r"url should start with a scheme", fn ->
      parse_url("eric:hunter2@host:123/mydb")
    end
    assert_raise Ecto.InvalidURL, ~r"path should be a database name", fn ->
      parse_url("ecto://eric:hunter2@host:123/a/b/c")
    end

    assert_raise Ecto.InvalidURL, ~r"path should be a database name", fn ->
      parse_url("ecto://eric:hunter2@host:123/")
    end
  end

  test "underscore/2" do
    assert underscore("Foo") == "foo"
    assert underscore("FooBar") == "foo_bar"
  end
end
