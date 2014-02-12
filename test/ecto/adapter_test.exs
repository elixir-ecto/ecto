defmodule Ecto.AdapterTest do
  use ExUnit.Case, async: true

  defmodule MockAdapter do
    defmacro __using__(_), do: :ok
    def start_link(_repo, opts), do: { :ok, opts }
  end

  defmodule MockRepo do
    use Ecto.Repo, adapter: MockAdapter

    def url do
      Process.get(:url)
    end
  end

  defp parse_url(url) do
    Process.put(:url, url)
    { :ok, opts } = MockRepo.start_link
    opts
  end

  test "receives parsed url on start_link" do
    url = parse_url("ecto://eric:hunter2@host:12345/mydb?size=10&a=b")
    assert { :password, "hunter2" } in url
    assert { :username, "eric" } in url
    assert { :hostname, "host" } in url
    assert { :database, "mydb" } in url
    assert { :port, 12345 } in url
    assert { :size, "10" } in url
    assert { :a, "b" } in url
  end

  test "does not receive invalid urls" do
    assert_raise Ecto.InvalidURL, ~r"url should start with a scheme", fn ->
      parse_url("eric:hunter2@host:123/mydb")
    end

    assert_raise Ecto.InvalidURL, ~r"url has to contain a username", fn ->
      parse_url("ecto://host:123/mydb")
    end

    assert_raise Ecto.InvalidURL, ~r"path should be a database name", fn ->
      parse_url("ecto://eric:hunter2@host:123/a/b/c")
    end

    assert_raise Ecto.InvalidURL, ~r"path should be a database name", fn ->
      parse_url("ecto://eric:hunter2@host:123/")
    end
  end

  test "receives parsed url with optional password" do
    refute parse_url("ecto://eric@host:123/mydb")[:password]
  end
end