defmodule Ecto.Pools.Poolboy.WorkerTest do
  use ExUnit.Case, async: true

  alias Ecto.TestPool
  alias Ecto.TestPool.Connection

  @timeout :infinity

  test "worker starts without an active connection but connects on transaction" do
    {:ok, pool} = TestPool.start_link([timeout: @timeout, adapter: Ecto.TestAdapter])
    worker = :poolboy.checkout(pool, false)
    assert Process.alive?(worker)
    refute :sys.get_state(worker).conn
    :poolboy.checkin(pool, worker)

    TestPool.transaction(pool, @timeout, fn(:opened, _ref, {Connection, conn}, _) ->
      assert Process.alive?(conn)
    end)
  end

  test "worker starts with an active connection" do
    {:ok, pool} = TestPool.start_link([lazy: false, timeout: @timeout, adapter: Ecto.TestAdapter])
    worker = :poolboy.checkout(pool, false)
    assert Process.alive?(worker)
    assert :sys.get_state(worker).conn
  end
end
