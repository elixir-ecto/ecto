defmodule Ecto.Repo.SupervisorTest do
  use ExUnit.Case, async: true

  import Ecto.Repo.Supervisor

  defp put_env(env) do
    Application.put_env(:ecto, __MODULE__, env)
  end

  defp normalize(config) do
    config |> Keyword.drop([:timeout, :pool_size, :telemetry_prefix]) |> Enum.sort()
  end

  test "invokes the init/2 callback on start", context do
    {:ok, _} =
      Ecto.TestRepo.start_link(parent: self(), name: context.test, query_cache_owner: false)

    assert_receive {Ecto.TestRepo, :supervisor, _}
  end

  test "invokes the init/2 callback on config" do
    assert Ecto.TestRepo.config() |> normalize() ==
             [
               database: "hello",
               hostname: "local",
               otp_app: :ecto,
               password: "pass",
               scheme: "ecto",
               user: "invalid",
               username: "user"
             ]
  end

  def handle_event(event, measurements, metadata, %{pid: pid}) do
    send(pid, {event, measurements, metadata})
  end

  test "emits telemetry event upon repo start" do
    :telemetry.attach_many(
      :telemetry_test,
      [[:ecto, :repo, :init]],
      &__MODULE__.handle_event/4,
      %{pid: self()}
    )

    Ecto.TestRepo.start_link(name: :telemetry_test)

    assert_receive {[:ecto, :repo, :init], _, %{repo: Ecto.TestRepo, opts: opts}}
    assert opts[:telemetry_prefix] == [:ecto, :test_repo]
    assert opts[:name] == :telemetry_test

    :telemetry.detach(:telemetry_test)
  end

  test "reads otp app configuration" do
    put_env(database: "hello")
    {:ok, config} = init_config(:runtime, __MODULE__, :ecto, [])

    assert normalize(config) ==
             [database: "hello", otp_app: :ecto]
  end

  test "merges url into configuration" do
    put_env(database: "hello", url: "ecto://eric:hunter2@host:12345/mydb")
    {:ok, config} = init_config(:runtime, __MODULE__, :ecto, extra: "extra")

    assert normalize(config) ==
             [
               database: "mydb",
               extra: "extra",
               hostname: "host",
               otp_app: :ecto,
               password: "hunter2",
               port: 12345,
               scheme: "ecto",
               username: "eric"
             ]
  end

  test "ignores empty hostname" do
    put_env(database: "hello", url: "ecto:///mydb")
    {:ok, config} = init_config(:runtime, __MODULE__, :ecto, extra: "extra")
    assert normalize(config) == [database: "mydb", extra: "extra", otp_app: :ecto, scheme: "ecto"]
  end

  test "is no-op for nil or empty URL" do
    put_env(database: "hello", url: nil)
    {:ok, config} = init_config(:runtime, __MODULE__, :ecto, [])

    assert normalize(config) ==
             [database: "hello", otp_app: :ecto]

    put_env(database: "hello", url: "")
    {:ok, config} = init_config(:runtime, __MODULE__, :ecto, [])

    assert normalize(config) ==
             [database: "hello", otp_app: :ecto]
  end

  test "works without an environment" do
    Application.delete_env(:ecto, __MODULE__)
    {:ok, config} = init_config(:runtime, __MODULE__, :ecto, [])
    assert normalize(config) == [otp_app: :ecto]
  end

  describe "parse_url/1" do
    test "returns empty list when URL is blank" do
      assert parse_url("") == []
    end

    test "parses URL options" do
      encoded_url = URI.encode("ecto://eric:it+й@host:12345/mydb")

      url = parse_url(encoded_url)

      assert {:password, "it+й"} in url
      assert {:username, "eric"} in url
      assert {:hostname, "host"} in url
      assert {:database, "mydb"} in url
      assert {:port, 12345} in url
    end

    test "URL parsing handles encoded symbol #" do
      encoded_url = "ecto://eric:pass*%23word@host:12345/mydb"

      url = parse_url(encoded_url)

      assert {:password, "pass*#word"} in url
      assert {:username, "eric"} in url
      assert {:hostname, "host"} in url
      assert {:database, "mydb"} in url
      assert {:port, 12345} in url
    end

    test "parses empty username/password" do
      url = parse_url("ecto://host:12345/mydb")
      refute Keyword.has_key?(url, :username)
      refute Keyword.has_key?(url, :password)
    end

    test "parses multiple query string options" do
      encoded_url = URI.encode("ecto://eric:it+й@host:12345/mydb?ssl=true&timeout=1515")
      url = parse_url(encoded_url)
      assert {:ssl, true} in url
      assert {:timeout, 1515} in url

      encoded_url = URI.encode("ecto://eric:it+й@host:12345/mydb?ssl=verify_full&timeout=1515")
      url = parse_url(encoded_url)
      assert {:ssl, :verify_full} in url
      assert {:timeout, 1515} in url
    end

    test "supports integer query string options" do
      url = "ecto://eric:it+й@host:12345/mydb"

      encoded_url = URI.encode("#{url}?timeout=1000")
      assert {:timeout, 1000} in parse_url(encoded_url)

      encoded_url = URI.encode("#{url}?pool_size=42")
      assert {:pool_size, 42} in parse_url(encoded_url)

      encoded_url = URI.encode("#{url}?idle_interval=10000")
      assert {:idle_interval, 10000} in parse_url(encoded_url)
    end

    test "supports ssl query string option" do
      url = "ecto://eric:it+й@host:12345/mydb"

      encoded_url = URI.encode("#{url}?ssl=true")
      assert {:ssl, true} in parse_url(encoded_url)

      encoded_url = URI.encode("#{url}?ssl=false")
      assert {:ssl, false} in parse_url(encoded_url)
    end

    test "supports camelCase query string options" do
      encoded_url = URI.encode("ecto://eric:it+й@host:12345/mydb?currentSchema=my_schema")
      assert {:currentSchema, "my_schema"} in parse_url(encoded_url)
    end

    test "raises on invalid urls" do
      assert_raise Ecto.InvalidURLError, ~r"The parsed URL is: %URI\{", fn ->
        parse_url("eric:hunter2@host:123/mydb")
      end

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

      for key <- ["timeout", "pool_size", "idle_interval"] do
        assert_raise Ecto.InvalidURLError,
                     ~r"can not parse value `not_an_int` for parameter `#{key}` as an integer",
                     fn ->
                       parse_url("ecto://eric:it+й@host:12345/mydb?#{key}=not_an_int")
                     end
      end
    end
  end
end
