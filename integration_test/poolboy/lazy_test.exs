defmodule Ecto.Integration.LazyTest do
  use ExUnit.Case, async: true

  alias Ecto.Integration.TestPool
  alias Ecto.Integration.Pool.Connection

  @timeout :infinity

  test "worker starts without an active connection but connects on transaction" do
    {:ok, pool} = TestPool.start_link([])
    worker = :poolboy.checkout(pool, false)
    assert Process.alive?(worker)
    refute :sys.get_state(worker).conn
    :poolboy.checkin(pool, worker)

    TestPool.transaction(pool, @timeout, fn(_, {Connection, conn}, _, _) ->
      assert Process.alive?(conn)
    end)
  end

  test "worker starts with an active connection" do
    {:ok, pool} = TestPool.start_link([lazy: false])
    worker = :poolboy.checkout(pool, false)
    assert Process.alive?(worker)
    assert :sys.get_state(worker).conn
  end
end
