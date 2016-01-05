defmodule Ecto.LogProxy do
  @moduledoc false

  use DBConnection.Proxy
  alias Ecto.LogQuery

  def init(opts) do
    if Keyword.get(opts, :log, true) do
      {:ok, [init: System.monotonic_time()]}
    else
      {:ok, []}
    end
  end

  def checkin(_, _, conn, times), do: {:ok, conn, times}

  def handle_prepare(mod, %LogQuery{query: query} = log_query, opts, conn, times) do
    times = [{:query, System.monotonic_time()} | times]
    case apply(mod, :handle_prepare, [query, opts, conn]) do
      {:ok, query, conn} ->
        {:ok, %LogQuery{log_query | query: query, times: times}, conn, []}
      {tag, _, _} = error when tag in [:error, :disconnect] ->
        :erlang.append_element(error, [])
      other ->
        raise DBConnection.Error, "bad return value: #{inspect other}"
    end
  end
  def handle_prepare(mod, query, opts, conn, _) do
    case apply(mod, :handle_prepare, [query, opts, conn]) do
      {:ok, _, _} = ok ->
        :erlang.append_element(ok, [])
      {tag, _, _} = error when tag in [:error, :disconnect] ->
        :erlang.append_element(error, [])
      other ->
        raise DBConnection.Error, "bad return value: #{inspect other}"
    end
  end

  def handle_execute_close(mod, %LogQuery{query: query}, params, opts, conn, []) do
    case apply(mod, :handle_execute_close, [query, params, opts, conn]) do
      {:ok, res, conn} ->
        {:ok, res, conn, []}
      {:prepare, _} = prepare ->
        :erlang.append_element(prepare, [])
      {tag, _, _} = error when tag in [:error, :disconnect] ->
        :erlang.append_element(error, [])
      other ->
        raise DBConnection.Error, "bad return value: #{inspect other}"
    end
  end
  def handle_execute_close(mod, query, params, opts, conn, []) do
    case apply(mod, :handle_execute_close, [query, params, opts, conn]) do
      {:ok, _, _} = ok ->
        :erlang.append_element(ok, [])
      {:prepare, _} = prepare ->
        :erlang.append_element(prepare, [])
      {tag, _, _} = error when tag in [:error, :disconnect] ->
        :erlang.append_element(error, [])
      other ->
        raise DBConnection.Error, "bad return value: #{inspect other}"
    end
  end

  def handle_begin(mod, opts, conn, state) do
    transaction(mod, :handle_begin, opts, conn, :BEGIN, state)
  end

  def handle_commit(mod, opts, conn, state) do
    transaction(mod, :handle_commit, opts, conn, :COMMIT, state)
  end

  def handle_rollback(mod, opts, conn, state) do
    transaction(mod, :handle_rollback, opts, conn, :ROLLBACK, state)
  end

  ## Helpers

  defp transaction(mod, fun, opts, conn, query, state) do
    if Keyword.get(opts, :log, true) do
      log_transaction(mod, fun, opts, conn, query, state)
    else
      handle_transaction(mod, fun, opts, conn, state)
    end
  end

  defp log_transaction(mod, fun, opts, conn, query, times) do
    times = [query: System.monotonic_time()] ++ times
    case apply(mod, fun, [opts, conn]) do
      {:ok, _} = ok ->
        log_transaction(query, :ok, times, opts)
        :erlang.append_element(ok, [])
      {tag, err, _} = error when tag in [:error, :disconnect] ->
        log_transaction(query, {:error, err}, times, opts)
        :erlang.append_element(error, [])
      other ->
        raise DBConnection.Error, "bad return value: #{inspect other}"
    end
  end

  defp log_transaction(query, result, times, opts) do
    entry = Ecto.LogEntry.new(query, nil, result, times)
    log = Keyword.fetch!(opts, :logger)
    log.(entry)
  end

  defp handle_transaction(mod, fun, opts, conn, _) do
    case apply(mod, fun, [opts, conn]) do
      {:ok, _} = ok ->
        :erlang.append_element(ok, [])
      {tag, _, _} = error when tag in [:error, :disconnect] ->
        :erlang.append_element(error, [])
      other ->
        raise DBConnection.Error, "bad return value: #{inspect other}"
    end
  end
end
