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

    diff = System.convert_time_unit(1, :microsecond, :native)
    entry = %{entry | params: [1, 2, 3], query_time: 2100 * diff, queue_time: 100 * diff}
    assert to_binary(entry) == "QUERY OK db=2.1ms queue=0.1ms\ndone [1, 2, 3]"

    entry = %{entry | params: [1, 2, 3], query_time: 2100 * diff, queue_time: 100 * diff,
                                         result: {:error, :error}}
    assert to_binary(entry) == "QUERY ERROR db=2.1ms queue=0.1ms\ndone [1, 2, 3]"

    entry = %{entry | params: [1, 2, 3], query_time: 2100 * diff, decode_time: 500 * diff,
                                         queue_time: 100 * diff, result: {:error, :error}}
    assert to_binary(entry) == "QUERY ERROR db=2.1ms decode=0.5ms queue=0.1ms\ndone [1, 2, 3]"

    entry = %{entry | source: "test"}
    assert to_binary(entry) == "QUERY ERROR source=\"test\" db=2.1ms decode=0.5ms queue=0.1ms\ndone [1, 2, 3]"
  end

  defp to_binary(entry) do
    entry |> to_iodata |> elem(1) |> IO.iodata_to_binary
  end
end
