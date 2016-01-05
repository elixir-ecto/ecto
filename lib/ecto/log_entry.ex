defmodule Ecto.LogEntry do
  @doc """
  Struct used for logging entries.

  It is composed of the following fields:

    * query - the query as iodata or a function that when invoked
      resolves to iodata;
    * params - the query parameters;
    * result - the query result as an `:ok` or `:error` tuple;
    * query_time - the time spent executing the query in microseconds;
    * decode_time - the time spent decoding the result in microseconds (it may be nil);
    * queue_time - the time spent to check the connection out in microseconds (it may be nil);
    * connection_pid - the connection process that executed the query
  """

  alias Ecto.LogEntry

  @type t :: %LogEntry{query: iodata | (t -> iodata), params: [term],
                       query_time: integer, decode_time: integer | nil,
                       queue_time: integer | nil, connection_pid: pid | nil,
                       result: {:ok, term} | {:error, Exception.t}}
  defstruct query: nil, params: [], query_time: nil, decode_time: nil,
            queue_time: nil, result: nil, connection_pid: nil

  @doc """
  Resolves a log entry.

  In case the query is represented by a function for lazy
  computation, this function resolves it into iodata.
  """
  def resolve(%LogEntry{query: fun} = entry) when is_function(fun) do
    %{entry | query: fun.(entry)}
  end

  def resolve(%LogEntry{} = entry) do
    entry
  end

  @doc """
  Converts a log entry into iodata.

  The entry is automatically resolved if it hasn't been yet.
  """
  def to_iodata(entry) do
    %{query_time: query_time, decode_time: decode_time, queue_time: queue_time,
      params: params, query: query, result: result} = entry = resolve(entry)

    params = Enum.map params, fn
      %Ecto.Query.Tagged{value: value} -> value
      value -> value
    end

    {entry, [query, ?\s, inspect(params, char_lists: false), ?\s, ok_error(result),
             time("query", query_time, true), time("decode", decode_time, false),
             time("queue", queue_time, false)]}
  end

  @doc false
  def new(query, params, result, times) do
    now = System.monotonic_time()
    lazy_query = fn(_) -> to_string(query) end
    entry = %Ecto.LogEntry{query: lazy_query, params: params, result: result}
    {_, entry} = Enum.reduce(times, {now, entry}, &put_time/2)
    entry
  end

  ## Helpers

  defp ok_error({:ok, _}),    do: "OK"
  defp ok_error({:error, _}), do: "ERROR"

  defp time(_label, nil, _force), do: []
  defp time(label, time, force) do
    ms = div(time, 100) / 10
    if force or ms > 0 do
      [?\s, label, ?=, :io_lib_format.fwrite_g(ms), ?m, ?s]
    else
      []
    end
  end

  defp put_time({:decode, decode}, {done, entry}) do
    {decode, %{entry | decode_time: convert_time(done - decode)}}
  end
  defp put_time({:query, query}, {done, entry}) do
    {query, %{entry | query_time: convert_time(done - query)}}
  end
  defp put_time({:init, init}, {done, entry}) do
    {init, %{entry | queue_time: convert_time(done - init)}}
  end

  defp convert_time(time) do
    System.convert_time_unit(time, :native, :micro_seconds)
  end
end
