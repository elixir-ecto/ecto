defmodule Ecto.LogQuery do
  @moduledoc false

  defstruct [query: nil, params: nil, times: []]
end

defimpl DBConnection.Query, for: Ecto.LogQuery do
  def parse(%Ecto.LogQuery{query: query} = log_query, opts) do
    if Keyword.get(opts, :log, true) do
      %Ecto.LogQuery{log_query | query: DBConnection.Query.parse(query, opts)}
    else
      DBConnection.Query.parse(query, opts)
    end
  end

  def describe(%Ecto.LogQuery{query: query} = log_query, opts) do
    %Ecto.LogQuery{log_query | query: DBConnection.Query.describe(query, opts)}
  end

  def encode(%Ecto.LogQuery{query: query}, params, opts) do
    DBConnection.Query.encode(query, params, opts)
  end

  def decode(log_query, res, opts) do
    decode = System.monotonic_time()
    %Ecto.LogQuery{query: query, params: params, times: times} = log_query
    res = DBConnection.Query.decode(query, res, opts)

    times = [decode: decode] ++ times
    entry = Ecto.LogEntry.new(query, params, {:ok, res}, times)

    log = Keyword.fetch!(opts, :logger)
    log.(entry)

    res
  end
end
