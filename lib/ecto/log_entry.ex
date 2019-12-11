defmodule Ecto.LogEntry do
  @moduledoc false
  # TODO: Remove me in future versions
  alias Ecto.LogEntry

  @type t :: %LogEntry{
          query: String.t(),
          source: String.t() | Enum.t() | nil,
          params: [term],
          query_time: integer | nil,
          decode_time: integer | nil,
          queue_time: integer | nil,
          result: {:ok, term} | {:error, Exception.t()}
        }

  defstruct query: nil,
            source: nil,
            params: [],
            query_time: nil,
            decode_time: nil,
            queue_time: nil,
            result: nil

  require Logger

  @doc """
  Logs the given entry in the given level.

  The logger call won't be removed at compile time as
  custom level is given.
  """
  @deprecated "Use Telemetry instead"
  def log(entry, level \\ :debug, metadata \\ []) do
    Logger.log(level, fn -> to_iodata(entry) end, metadata)
  end

  @doc """
  Converts a log entry into iodata.
  """
  @deprecated "Use Telemetry instead"
  def to_iodata(entry) do
    %{
      query_time: query_time,
      decode_time: decode_time,
      queue_time: queue_time,
      params: params,
      query: query,
      result: result,
      source: source
    } = entry

    params =
      Enum.map(params, fn
        %Ecto.Query.Tagged{value: value} -> value
        value -> value
      end)

    [
      "QUERY",
      ?\s,
      ok_error(result),
      ok_source(source),
      time("db", query_time, true),
      time("decode", decode_time, false),
      time("queue", queue_time, false),
      ?\n,
      query,
      ?\s,
      inspect(params, charlists: false)
    ]
  end

  ## Helpers

  defp ok_error({:ok, _}), do: "OK"
  defp ok_error({:error, _}), do: "ERROR"

  defp ok_source(nil), do: ""
  defp ok_source(source), do: " source=#{inspect(source)}"

  defp time(_label, nil, _force), do: []

  defp time(label, time, force) do
    us = System.convert_time_unit(time, :native, :microsecond)
    ms = div(us, 100) / 10

    if force or ms > 0 do
      [?\s, label, ?=, :io_lib_format.fwrite_g(ms), ?m, ?s]
    else
      []
    end
  end
end
