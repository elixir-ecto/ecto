defmodule Ecto.Pools.SojournBroker.Broker do
  @moduledoc false
  @behaviour :sbroker

  @doc false
  def init(opts) do
    out      = Keyword.get(opts, :queue_out, :out)
    timeout  = Keyword.get(opts, :queue_timeout, 5_000)
    drop     = Keyword.get(opts, :queue_drop, :drop)
    size     = Keyword.get(opts, :queue_size, 64)

    client_queue = {:sbroker_timeout_queue, {out, timeout * 1_000, drop, size}}
    worker_queue = {:sbroker_drop_queue, {:out_r, :drop, :infinity}}

    {:ok, {client_queue, worker_queue, div(timeout, 2)}}
  end
end
