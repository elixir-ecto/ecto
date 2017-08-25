defmodule Ecto.Repo.SupervisorTest do
  use ExUnit.Case, async: true

  import Ecto.Repo.Supervisor

  defp put_env(env) do
    Application.put_env(:ecto, __MODULE__, env)
  end

  defp normalize(config) do
    config |> Keyword.drop([:timeout, :pool_timeout]) |> Enum.sort()
  end

  test "invokes the init/2 callback on start", context do
    {:ok, _} = Ecto.TestRepo.start_link(parent: self(), name: context.test, query_cache_owner: false)
    assert_receive {Ecto.TestRepo, :supervisor, _}
  end

  test "invokes the init/2 callback on config" do
    assert Ecto.TestRepo.config() |> normalize() ==
           [database: "hello", hostname: "local", otp_app: :ecto, password: "pass",
            repo: Ecto.TestRepo, user: "invalid", username: "user"]
  end

  test "reads otp app configuration" do
    put_env(database: "hello")
    {:ok, config} = runtime_config(:dry_run, __MODULE__, :ecto, [])
    assert normalize(config) ==
           [database: "hello", otp_app: :ecto, repo: __MODULE__]
  end

  test "merges url into configuration" do
    put_env(database: "hello", url: "ecto://eric:hunter2@host:12345/mydb")
    {:ok, config} = runtime_config(:dry_run, __MODULE__, :ecto, [extra: "extra"])
    assert normalize(config) ==
           [database: "mydb", extra: "extra", hostname: "host", otp_app: :ecto,
            password: "hunter2", port: 12345, repo: __MODULE__, username: "eric"]
  end

  test "is no-op for nil or empty URL" do
    put_env(database: "hello", url: nil)
    {:ok, config} = runtime_config(:dry_run, __MODULE__, :ecto, [])
    assert normalize(config) ==
           [database: "hello", otp_app: :ecto, repo: Ecto.Repo.SupervisorTest]

    put_env(database: "hello", url: "")
    {:ok, config} = runtime_config(:dry_run, __MODULE__, :ecto, [])
    assert normalize(config) ==
           [database: "hello", otp_app: :ecto, repo: Ecto.Repo.SupervisorTest]
  end

  test "parse_url options" do
    encoded_url = URI.encode("ecto://eric:it+й@host:12345/mydb")
    url = parse_url(encoded_url)
    assert {:password, "it+й"} in url
    assert {:username, "eric"} in url
    assert {:hostname, "host"} in url
    assert {:database, "mydb"} in url
    assert {:port, 12345} in url
  end

  test "parse_url query string" do
    encoded_url = URI.encode("ecto://eric:it+й@host:12345/mydb?ssl=true&pool_timeout=1000&timeout=1000&pool_size=42")
    url = parse_url(encoded_url)
    assert {:password, "it+й"} in url
    assert {:username, "eric"} in url
    assert {:hostname, "host"} in url
    assert {:database, "mydb"} in url
    assert {:port, 12345} in url
    assert {:ssl, true} in url
    assert {:timeout, 1000} in url
    assert {:pool_timeout, 1000} in url
    assert {:pool_size, 42} in url
  end

  test "parse_url returns no config when blank" do
    assert parse_url("") == []
  end

  test "parse_url keeps false values" do
    assert {:ssl, false} in parse_url("ecto://eric:it+й@host:12345/mydb?ssl=false")
  end

  test "parse_urls empty username/password" do
    url = parse_url("ecto://host:12345/mydb")
    assert !Keyword.has_key?(url, :username)
    assert !Keyword.has_key?(url, :password)
  end

  test "fail on invalid urls" do
    assert_raise Ecto.InvalidURLError, ~r"host is not present", fn ->
      parse_url("eric:hunter2@host:123/mydb")
    end

    assert_raise Ecto.InvalidURLError, ~r"path should be a database name", fn ->
      parse_url("ecto://eric:hunter2@host:123/a/b/c")
    end

    assert_raise Ecto.InvalidURLError, ~r"path should be a database name", fn ->
      parse_url("ecto://eric:hunter2@host:123/")
    end

    assert_raise Ecto.InvalidURLError, ~r"path should be a database name", fn ->
      parse_url("ecto://eric:hunter2@host:123")
    end

    assert_raise Ecto.InvalidURLError, ~r"unsupported query parameter `uknown_param`", fn ->
      parse_url("ecto://eric:it+й@host:12345/mydb?uknown_param=value")
    end

    for key <- ["timeout", "pool_size", "pool_timeout"] do
      assert_raise Ecto.InvalidURLError, ~r"can not parse value `not_an_int` for parameter `#{key}` as an integer", fn ->
        parse_url("ecto://eric:it+й@host:12345/mydb?#{key}=not_an_int")
      end
    end
  end
end
