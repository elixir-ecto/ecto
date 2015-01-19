defmodule Ecto.Integration.WorkerTest do
  use ExUnit.Case
  alias Ecto.Adapters.Postgres.Worker

  test "worker starts without an active connection" do
    {:ok, worker} = Worker.start_link(worker_opts(database: "gary"))

    assert Process.alive?(worker)
    refute :sys.get_state(worker).conn
  end

  test "worker starts with an active connection" do
    {:ok, worker} = Worker.start_link(worker_opts(lazy: false))

    assert Process.alive?(worker)
    assert :sys.get_state(worker).conn
  end

  test "worker survives, connection stops if caller dies" do
    {:ok, worker} = Worker.start(worker_opts(lazy: false))
    conn = :sys.get_state(worker).conn
    conn_mon   = Process.monitor(conn)
    worker_mon = Process.monitor(worker)

    spawn(fn ->
      Worker.link_me(worker)
      Worker.query!(worker, "SELECT TRUE", [], timeout: 5000)
    end)

    assert_receive {:DOWN, ^conn_mon, :process, ^conn, _}, 1000
    refute_received {:DOWN, ^worker_mon, :process, ^worker, _}
    refute :sys.get_state(worker).conn
  end

  test "worker survives if connection dies outside of transaction" do
    {:ok, worker} = Worker.start(worker_opts(lazy: false))
    conn = :sys.get_state(worker).conn
    conn_mon   = Process.monitor(conn)
    worker_mon = Process.monitor(worker)

    Process.exit(conn, :shutdown)

    assert_receive {:DOWN, ^conn_mon, :process, ^conn, _}, 1000
    refute_received {:DOWN, ^worker_mon, :process, ^worker, _}
    refute :sys.get_state(worker).conn
  end

  test "worker dies if connection dies inside of transaction" do
    {:ok, worker} = Worker.start(worker_opts(lazy: false))
    conn = :sys.get_state(worker).conn
    conn_mon   = Process.monitor(conn)
    worker_mon = Process.monitor(worker)

    Worker.begin!(worker, [timeout: :infinity])
    Process.exit(conn, :shutdown)

    assert_receive {:DOWN, ^conn_mon, :process, ^conn, _}, 1000
    assert_receive {:DOWN, ^worker_mon, :process, ^worker, _}, 1000
  end

  defp worker_opts(opts) do
    opts
    |> Keyword.put_new(:hostname, "localhost")
    |> Keyword.put_new(:database, "ecto_test")
    |> Keyword.put_new(:username, "postgres")
    |> Keyword.put_new(:password, "postgres")
  end
end
