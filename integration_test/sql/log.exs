defmodule Ecto.Integration.LogTest do
  use Ecto.Integration.Case

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  test "log entry logged on query" do
    log = fn entry ->
      assert %Ecto.LogEntry{params: [], result: {:ok, _}} = entry
      assert is_integer(entry.query_time) and entry.query_time >= 0
      assert is_integer(entry.decode_time) and entry.query_time >= 0
      assert is_integer(entry.queue_time) and entry.queue_time >= 0
      send(self(), :logged)
    end
    Process.put(:on_log, log)

    _ = TestRepo.insert!(%Post{title: "1"})
    assert_received :logged
  end

  test "log entry not logged when log is false" do
    Process.put(:on_log, fn -> flunk("logged") end)
    TestRepo.insert!(%Post{title: "1"}, [log: false])
  end
end
