Logger.configure_backend(:console, metadata: [:sample])

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

    query_time = :erlang.convert_time_unit(210000, :micro_seconds, :native)
    queue_time = :erlang.convert_time_unit(10000, :micro_seconds, :native)
    decode_time = :erlang.convert_time_unit(50000, :micro_seconds, :native)

    entry = %{entry | params: [1, 2, 3], query_time: query_time, queue_time: queue_time}
    assert to_binary(entry) == "QUERY OK db=210.0ms queue=10.0ms\ndone [1, 2, 3]"

    entry = %{entry | params: [1, 2, 3], query_time: query_time, queue_time: queue_time,
                                         result: {:error, :error}}
    assert to_binary(entry) == "QUERY ERROR db=210.0ms queue=10.0ms\ndone [1, 2, 3]"

    entry = %{entry | params: [1, 2, 3], query_time: query_time, decode_time: decode_time,
                                         queue_time: queue_time, result: {:error, :error}}
    assert to_binary(entry) == "QUERY ERROR db=210.0ms decode=50.0ms queue=10.0ms\ndone [1, 2, 3]"

    entry = %{entry | source: "test"}
    assert to_binary(entry) == "QUERY ERROR source=\"test\" db=210.0ms decode=50.0ms queue=10.0ms\ndone [1, 2, 3]"
  end

  test "converts from struct entry to iodata" do
    entry = %LogEntry{query: "done", result: {:ok, []}}
    assert to_binary(Map.from_struct(entry)) == "QUERY OK\ndone []"
  end

  test "logs metadata" do
    message =
      ExUnit.CaptureLog.capture_log(fn ->
        entry = %LogEntry{query: "done", result: {:ok, []}}
        assert Ecto.LogEntry.log(entry, :error, sample: "metadata")
      end)

    assert message =~ "[error] QUERY OK\ndone []"
    assert message =~ "sample=metadata"
  end

  defp to_binary(entry) do
    entry |> to_iodata() |> IO.iodata_to_binary()
  end
end
