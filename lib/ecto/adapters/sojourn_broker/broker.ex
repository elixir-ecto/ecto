defmodule Ecto.Adapters.SojournBroker.Broker do
  @moduledoc """
  Default `:sbroker` callback module.

  ### Options

    * `:queue_timeout` - The amount of time in milliseconds to wait in queue (default: 5000)
    * `:queue_out` - Either `:out` for a FIFO queue or `:out_r` for a LIFO queue (default: :out)
    * `:queue_drop` - Either `:drop` for head drop on max size or `:drop_r` for tail drop (default: :drop)
    * `:queue_size` - The maximum size of the queue (default: 64)

  """

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
