defmodule Ecto.Adapters.WorkerTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.Worker

  defmodule Connection do
    def connect(_opts) do
      Agent.start_link(fn -> [] end)
    end

    def disconnect(conn) do
      Agent.stop(conn)
    end
  end

  @timeout :infinity

  test "worker starts without an active connection" do
    {:ok, worker} = Worker.start_link({Connection, []})

    assert Process.alive?(worker)
    refute :sys.get_state(worker).conn
  end

  test "worker starts with an active connection" do
    {:ok, worker} = Worker.start_link({Connection, lazy: false})

    assert Process.alive?(worker)
    assert :sys.get_state(worker).conn
  end
end
