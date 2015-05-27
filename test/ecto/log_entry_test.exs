defmodule Ecto.LogEntryTest do
  use ExUnit.Case, async: true

  alias  Ecto.LogEntry
  import Ecto.LogEntry

  test "can be resolved" do
    entry = %LogEntry{query: fn %LogEntry{} -> "done" end}

    # Resolve once
    entry = resolve(entry)
    assert entry.query == "done"

    # It can also be resolved multiple times
    entry = resolve(entry)
    assert entry.query == "done"
  end

  test "converts entry to iodata" do
    entry = %LogEntry{query: fn _ -> "done" end, params: []}
    assert to_binary(entry) == "done []"

    entry = %LogEntry{query: "done", params: [1, 2, 3]}
    assert to_binary(entry) == "done [1, 2, 3]"

    entry = %LogEntry{query: "done", params: [%Ecto.Query.Tagged{value: 1}, 2, 3]}
    assert to_binary(entry) == "done [1, 2, 3]"

    entry = %LogEntry{query: "done", params: [1, 2, 3], query_time: 0}
    assert to_binary(entry) == "done [1, 2, 3] query=0.0ms"

    entry = %LogEntry{query: "done", params: [1, 2, 3], query_time: 0, queue_time: 0}
    assert to_binary(entry) == "done [1, 2, 3] query=0.0ms"

    entry = %LogEntry{query: "done", params: [1, 2, 3], query_time: 2100, queue_time: 100}
    assert to_binary(entry) == "done [1, 2, 3] query=2.1ms queue=0.1ms"
  end

  defp to_binary(entry) do
    entry |> to_iodata |> elem(1) |> IO.iodata_to_binary
  end
end
