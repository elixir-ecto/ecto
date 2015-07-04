defmodule Ecto.Integration.WorkerTest do
  use ExUnit.Case, async: true

  alias Ecto.Integration.TestPool
  alias Ecto.Integration.Pool.Connection

  @timeout :infinity

  setup context do
    case = context[:case]
    test = context[:test]
    {:ok, [pool: Module.concat(case, test)]}
  end

  test "worker restarts connection when waiting", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([name: pool])

    {:ok, conn1} = TestPool.transaction(pool, @timeout,
      fn(_, {Connection, conn}, _, _) ->
        conn
      end)

    await_len_r(pool, 1)

    ref = Process.monitor(conn1)
    Process.exit(conn1, :kill)
    receive do: ({:DOWN, ^ref, _, _, _} -> :ok)

    await_len_r(pool, 0)

    {:ok, conn2} = TestPool.transaction(pool, @timeout,
      fn(_, {Connection, conn}, _, _) ->
        conn
      end)

    assert conn1 != conn2
  end

  defp await_len_r(pool, len) do
    case :sbroker.len_r(pool, @timeout) do
      ^len -> :ok
      _    -> await_len_r(pool, len)
    end
  end
end
