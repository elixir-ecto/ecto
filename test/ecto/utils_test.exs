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

  test "parse_url return list with db options" do
    opt = parse_url("ecto://eric:hunter2@host:12345/mydb?size=10&a=b", %{lc_collate: "en_IE.UTF-8"})
    assert {:encoding, "UTF8"} in opt
    assert {:lc_collate, "en_IE.UTF-8"} in opt
  end

  test "merge_db_options" do
    new_opt = %{lc_collate: "en_IE.UTF-8", lc_ctype: "en_IE.UTF-8"}
    opt = merge_db_options(new_opt)

    assert opt[:lc_collate] == new_opt[:lc_collate]
    assert opt[:lc_ctype] == new_opt[:lc_ctype]
    assert is_list opt
  end

  test "when merge_db_options is empty " do
    default_val = %{template: ~s(template0),
      encoding: ~s(UTF8),
      lc_collate: ~s(en_US.UTF-8),
      lc_ctype: ~s(en_US.UTF-8)
    }

    opt = merge_db_options
    assert opt[:lc_collate] == default_val[:lc_collate]
    assert opt[:lc_ctype] == default_val[:lc_ctype]
    assert is_list opt
  end

  test "parse_urls empty username/password" do
    url = parse_url("ecto://host:12345/mydb?size=10&a=b")
    assert !Dict.has_key?(url, :username)
    assert !Dict.has_key?(url, :password)
  end

  test "fail on invalid urls" do
    assert_raise Ecto.InvalidURLError, ~r"url should start with a scheme", fn ->
      parse_url("eric:hunter2@host:123/mydb")
    end

    assert_raise Ecto.InvalidURLError, ~r"path should be a database name", fn ->
      parse_url("ecto://eric:hunter2@host:123/a/b/c")
    end

    assert_raise Ecto.InvalidURLError, ~r"path should be a database name", fn ->
      parse_url("ecto://eric:hunter2@host:123/")
    end
  end
end
