Code.require_file "../support/file_helpers.exs", __DIR__

defmodule Ecto.Integration.PoolTest do
  use ExUnit.Case, async: true

  pool =
    case System.get_env("ECTO_POOL") || "poolboy" do
      "poolboy"        -> Ecto.Pools.Poolboy
      "sojourn_broker" -> Ecto.Pools.SojournBroker
    end

  repo = Application.get_env(:ecto, Ecto.Integration.TestRepo) ||
         raise "could not find configuration for Ecto.Integration.TestRepo"

  Application.put_env(:ecto, __MODULE__.MockRepo,
                      [pool: pool, pool_size: 1] ++ repo)

  defmodule MockRepo do
    use Ecto.Repo, otp_app: :ecto

    def after_connect(conn) do
      send Application.get_env(:ecto, :pool_test_pid), {:after_connect, conn}
    end
  end

  defmodule MockPool do
    def start_link(_conn_mod, opts) do
      assert opts[:pool_name] == MockRepo.Alternative.Pool
      assert opts[:repo] == MockRepo
      assert opts[:foo] == :bar # Custom options are passed through
      Task.start_link(fn -> :timer.sleep(:infinity) end)
    end
  end

  setup do
    Application.put_env(:ecto, :pool_test_pid, self())
    :ok
  end

  test "starts repo with after_connect" do
    assert {:ok, _} = MockRepo.start_link(lazy: false, name: MockRepo.AfterConnect, query_cache_owner: false)
    assert_receive {:after_connect, pid} when is_pid(pid)
  end

  test "starts repo with different names" do
    assert {:ok, pool1} = MockRepo.start_link()
    assert {:error, {:already_started, _}} = MockRepo.start_link()

    assert {:ok, pool2} = MockRepo.start_link(name: MockRepo.Named, query_cache_owner: false)
    assert pool1 != pool2
  end

  test "starts repo with custom pool" do
    assert {:ok, _} =
      MockRepo.start_link(name: MockRepo.Alternative, pool: MockPool, foo: :bar, query_cache_owner: false)
  end
end
