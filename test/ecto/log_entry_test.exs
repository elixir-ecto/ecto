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
    entry = %LogEntry{query: "done", result: {:ok, []}}
    assert to_binary(entry) == "done [] OK"

    entry = %{entry | params: [1, 2, 3], result: {:ok, []}}
    assert to_binary(entry) == "done [1, 2, 3] OK"

    entry = %{entry | params: [9, 10, 11]}
    assert to_binary(entry) == "done [9, 10, 11] OK"

    entry = %{entry | params: [%Ecto.Query.Tagged{value: 1}, 2, 3]}
    assert to_binary(entry) == "done [1, 2, 3] OK"

    entry = %{entry | params: [1, 2, 3], query_time: 0}
    assert to_binary(entry) == "done [1, 2, 3] OK query=0.0ms"

    entry = %{entry | params: [1, 2, 3], query_time: 0, queue_time: 0}
    assert to_binary(entry) == "done [1, 2, 3] OK query=0.0ms"

    entry = %{entry | params: [1, 2, 3], query_time: 2100, queue_time: 100}
    assert to_binary(entry) == "done [1, 2, 3] OK query=2.1ms queue=0.1ms"

    entry = %{entry | params: [1, 2, 3], query_time: 2100, queue_time: 100, result: {:error, :error}}
    assert to_binary(entry) == "done [1, 2, 3] ERROR query=2.1ms queue=0.1ms"

    entry = %{entry | params: [1, 2, 3], query_time: 2100, decode_time: 500, queue_time: 100, result: {:error, :error}}
    assert to_binary(entry) == "done [1, 2, 3] ERROR query=2.1ms decode=0.5ms queue=0.1ms"
  end

  test "resolves when converting entry to iodata" do
    entry = %LogEntry{query: fn _ -> "done" end, params: [], result: {:ok, []}}
    {entry, iodata} = to_iodata(entry)
    assert entry.query == "done"
    assert IO.iodata_to_binary(iodata) == "done [] OK"
  end

  defp to_binary(entry) do
    entry |> to_iodata |> elem(1) |> IO.iodata_to_binary
  end
end
