defmodule Ecto.Pool.RunTest do
  use ExUnit.Case, async: true

  alias Ecto.TestPool

  @timeout :infinity

  setup context do
    case = context[:case]
    test = context[:test]
    pool = Module.concat(case, test)
    {:ok, _} = TestPool.start_link([lazy: false, name: pool,
                                    timeout: @timeout, adapter: Ecto.TestAdapter])
    {:ok, [pool: pool]}
  end

  test "worker cleans up the connection when it crashes", context do
    pool = context[:pool]

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

  test "nested run has no queue time", context do
    pool = context[:pool]

    TestPool.transaction(pool, @timeout, fn(_, _, _, _) ->
      TestPool.run(pool, @timeout, fn({_mod, _conn}, queue_time) ->
        assert is_nil(queue_time)
      end)
    end)
  end

  test "does not disconnect if caller dies during run", context do
    pool = context[:pool]

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
