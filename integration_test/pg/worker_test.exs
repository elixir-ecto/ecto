defmodule Ecto.Integration.WorkerTest do
  use ExUnit.Case

  alias Ecto.Adapters.Postgres.Worker

  test "worker starts without an active connection" do
    { :ok, worker } = Worker.start_link(worker_opts(database: "gary"))

    assert Process.alive?(worker)
    refute :sys.get_state(worker) |> elem(1)
  end

  test "worker reconnects to database when connecton exits" do
    { :ok, worker } = Worker.start_link(worker_opts)

    assert Postgrex.Result[] = Worker.query!(worker, "SELECT TRUE")
    conn = :sys.get_state(worker) |> elem(1)

    Process.exit(conn, :normal)
    assert Postgrex.Result[] = Worker.query!(worker, "SELECT TRUE")
  end

  defp worker_opts(opts \\ []) do
    [ hostname: opts[:hostname] || "localhost",
      database: opts[:database] || "ecto_test",
      username: opts[:username] || "postgres",
      password: opts[:password] || "postgres" ]
  end
end
