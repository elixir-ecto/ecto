defmodule Ecto.Integration.WorkerTest do
  use ExUnit.Case

  alias Ecto.Adapters.Postgres.Worker

  test "worker starts without an active connection" do
    { :ok, worker } = Worker.start_link(worker_opts(database: "gary"))
    assert Process.alive?(worker)
  end

  test "worker reconnects to database when connecton exits" do
    { :ok, worker } = Worker.start_link(worker_opts)
    { :links, links } = Process.info(worker, :links)
    conn = Enum.first(Enum.reject(links, &(&1 == self)))
    Process.exit(conn, :normal)
    result = Worker.query!(worker, "SELECT TRUE")
    assert is_record(result, Postgrex.Result)
  end

  defp worker_opts(opts // []) do
    [ hostname: opts[:hostname] || "localhost",
      database: opts[:database] || "ecto_test",
      username: opts[:username] || "postgres",
      password: opts[:password] || "postgres" ]
  end
end
