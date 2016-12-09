defmodule Ecto.LogEntry do
  @moduledoc """
  Struct used for logging entries.

  It is composed of the following fields:

    * query - the query as string or a function that when invoked resolves to string;
    * source - the query data source;
    * params - the query parameters;
    * result - the query result as an `:ok` or `:error` tuple;
    * query_time - the time spent executing the query in native units;
    * decode_time - the time spent decoding the result in native units (it may be nil);
    * queue_time - the time spent to check the connection out in native units (it may be nil);
    * connection_pid - the connection process that executed the query;
    * ansi_color - the color that should be used when logging the entry.

  Notice all times are stored in native unit. You must convert them to
  the proper unit by using `System.convert_time_unit/3` before logging.
  """

  alias Ecto.LogEntry

  @type t :: %LogEntry{query: String.t | (t -> String.t), source: String.t | Enum.t | nil,
                       params: [term], query_time: integer, decode_time: integer | nil,
                       queue_time: integer | nil, connection_pid: pid | nil,
                       result: {:ok, term} | {:error, Exception.t},
                       ansi_color: IO.ANSI.ansicode | nil}

  defstruct query: nil, source: nil, params: [], query_time: nil, decode_time: nil,
            queue_time: nil, result: nil, connection_pid: nil, ansi_color: nil

  require Logger

  @doc """
  Logs the given entry in debug mode.

  The logger call will be removed at compile time if
  `compile_time_purge_level` is set to higher than debug.
  """
  def log(%{connection_pid: connection_pid, ansi_color: ansi_color} = entry) do
    Logger.debug(fn ->
      {_entry, iodata} = Ecto.LogEntry.to_iodata(entry)
      iodata
    end, ecto_conn_pid: connection_pid, ansi_color: ansi_color)
    entry
  end

  @doc """
  Logs the given entry in the given level.

  The logger call won't be removed at compile time as
  custom level is given.
  """
  def log(entry, level) do
    Logger.log(level, fn ->
      {_entry, iodata} = Ecto.LogEntry.to_iodata(entry)
      iodata
    end, ecto_conn_pid: entry.connection_pid)
    entry
  end

  @doc """
  Converts a log entry into iodata.

  The entry is automatically resolved if it hasn't been yet.
  """
  def to_iodata(entry) do
    %{query_time: query_time, decode_time: decode_time, queue_time: queue_time,
      params: params, query: query, result: result, source: source} = entry

    params = Enum.map params, fn
      %Ecto.Query.Tagged{value: value} -> value
      value -> value
    end

    {entry, ["QUERY", ?\s, ok_error(result), ok_source(source), time("db", query_time, true),
             time("decode", decode_time, false), time("queue", queue_time, false), ?\n,
             query, ?\s, inspect(params, charlists: false)]}
  end

  ## Helpers

  defp ok_error({:ok, _}),    do: "OK"
  defp ok_error({:error, _}), do: "ERROR"

  defp ok_source(nil),    do: ""
  defp ok_source(source), do: " source=#{inspect(source)}"

  defp time(_label, nil, _force), do: []
  defp time(label, time, force) do
    us = System.convert_time_unit(time, :native, :micro_seconds)
    ms = div(us, 100) / 10
    if force or ms > 0 do
      [?\s, label, ?=, :io_lib_format.fwrite_g(ms), ?m, ?s]
    else
      []
    end
  end
end
