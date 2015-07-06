defmodule Ecto.Integration.PoolRunTest do
  use ExUnit.Case, async: true

  alias Ecto.Integration.TestPool

  @timeout :infinity

  test "worker cleans up the connection when it crashes" do
    {:ok, pool} = TestPool.start_link([lazy: false])

    assert {:ok, conn1} =
      TestPool.run(pool, @timeout, fn({_mod, conn1}, queue_time) ->
        assert is_integer(queue_time)
        ref = Process.monitor(conn1)
        Process.exit(conn1, :kill)
        receive do: ({:DOWN, ^ref, _, _, _} -> :ok)
        conn1
      end)

    TestPool.run(pool, @timeout, fn({_mod, conn2}, queue_time) ->
      assert is_integer(queue_time)
      assert conn1 != conn2
      refute Process.alive?(conn1)
      assert Process.alive?(conn2)
    end)
  end

  test "nested run has no queue time" do
    {:ok, pool} = TestPool.start_link([lazy: false])

    TestPool.transaction(pool, @timeout, fn(_, _, _, _) ->
      TestPool.run(pool, @timeout, fn({_mod, _conn}, queue_time) ->
        assert is_nil(queue_time)
      end)
    end)
  end

  test "does not disconnect if caller dies during run" do
    {:ok, pool} = TestPool.start_link([lazy: false])

    _ = Process.flag(:trap_exit, true)
    parent = self()
    {:ok, task} = Task.start_link(fn ->
      TestPool.run(pool, @timeout, fn({_mod, conn1}, _) ->
        send(parent, {:go, self(), conn1})
        :timer.sleep(:infinity)
      end)
    end)

    assert_receive {:go, ^task, conn1}, @timeout
    Process.exit(task, :kill)
    assert_receive {:EXIT, ^task, :killed}, @timeout

    TestPool.run(pool, @timeout, fn({_mod, conn2}, _) ->
      assert assert conn1 == conn2
      assert Process.alive?(conn1)
    end)
  end
end
