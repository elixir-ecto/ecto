defmodule Ecto.Pools.Poolboy.WorkerTest do
  use ExUnit.Case, async: true

  alias Ecto.TestPool
  alias Ecto.TestPool.Connection

  @timeout :infinity

  setup context do
    case = context[:case]
    test = context[:test]
    {:ok, [pool: Module.concat(case, test)]}
  end

  test "worker starts without an active connection but connects on transaction", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([pool_name: pool])
    worker = :poolboy.checkout(pool, false)
    assert Process.alive?(worker)
    refute :sys.get_state(worker).conn
    :poolboy.checkin(pool, worker)

    TestPool.transaction(pool, @timeout, fn(:opened, _ref, {Connection, conn}, _) ->
      assert Process.alive?(conn)
    end)
  end

  test "worker starts with an active connection", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([pool_name: pool, lazy: false])
    worker = :poolboy.checkout(pool, false)
    assert Process.alive?(worker)
    assert :sys.get_state(worker).conn
  end
end
