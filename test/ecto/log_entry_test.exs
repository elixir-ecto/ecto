defmodule Ecto.LogEntryTest do
  use ExUnit.Case, async: true

  alias  Ecto.LogEntry
  import Ecto.LogEntry

  test "converts entry to iodata" do
    entry = %LogEntry{query: "done", result: {:ok, []}}
    assert to_binary(entry) == "QUERY OK\ndone []"

    entry = %{entry | params: [1, 2, 3], result: {:ok, []}}
    assert to_binary(entry) == "QUERY OK\ndone [1, 2, 3]"

    entry = %{entry | params: [9, 10, 11]}
    assert to_binary(entry) == "QUERY OK\ndone [9, 10, 11]"

    entry = %{entry | params: [%Ecto.Query.Tagged{value: 1}, 2, 3]}
    assert to_binary(entry) == "QUERY OK\ndone [1, 2, 3]"

    entry = %{entry | params: [1, 2, 3], query_time: 0}
    assert to_binary(entry) == "QUERY OK db=0.0ms\ndone [1, 2, 3]"

    entry = %{entry | params: [1, 2, 3], query_time: 0, queue_time: 0}
    assert to_binary(entry) == "QUERY OK db=0.0ms\ndone [1, 2, 3]"

    query_time = :erlang.convert_time_unit(2100, :micro_seconds, :native)
    queue_time = :erlang.convert_time_unit(100, :micro_seconds, :native)
    decode_time = :erlang.convert_time_unit(500, :micro_seconds, :native)

    entry = %{entry | params: [1, 2, 3], query_time: query_time, queue_time: queue_time}
    assert to_binary(entry) == "QUERY OK db=2.1ms queue=0.1ms\ndone [1, 2, 3]"

    entry = %{entry | params: [1, 2, 3], query_time: query_time, queue_time: queue_time,
                                         result: {:error, :error}}
    assert to_binary(entry) == "QUERY ERROR db=2.1ms queue=0.1ms\ndone [1, 2, 3]"

    entry = %{entry | params: [1, 2, 3], query_time: query_time, decode_time: decode_time,
                                         queue_time: queue_time, result: {:error, :error}}
    assert to_binary(entry) == "QUERY ERROR db=2.1ms decode=0.5ms queue=0.1ms\ndone [1, 2, 3]"

    entry = %{entry | source: "test"}
    assert to_binary(entry) == "QUERY ERROR source=\"test\" db=2.1ms decode=0.5ms queue=0.1ms\ndone [1, 2, 3]"
  end

  defp to_binary(entry) do
    entry |> to_iodata |> elem(1) |> IO.iodata_to_binary
  end
end
