defmodule Ecto.Pools.SojournBroker.CoDel do
  @moduledoc """
  CoDel based broker.

  Drops requests waiting for a connection using the CoDel algorithm. See
  `:sbroker_codel_queue` for more information.

  ### Options

  * `:queue_interval` - The first interval in milliseconds between drops when above target (default: `100`)
  * `:queue_target` - The target time in milliseconds for requests to wait in the queue (default: `div(queue_interval, 10)`)
  * `:queue_out` - Either `:out` for a FIFO queue or `:out_r` for a LIFO queue (default: `:out`)
  * `:queue_drop` - Either `:drop` for head drop on max size or `:drop_r` for tail drop (default: `:drop`)
  * `:queue_size` - The maximum size of the queue (default: `128`)

  """

  if Code.ensure_loaded?(:sbroker) do
    @behaviour :sbroker
  end

  @doc false
  def init(opts) do
    out      = Keyword.get(opts, :queue_out, :out)
    interval = Keyword.get(opts, :queue_interval, 100)
    target   = Keyword.get(opts, :queue_target, div(interval, 10))
    drop     = Keyword.get(opts, :queue_drop, :drop)
    size     = Keyword.get(opts, :queue_size, 128)

    client_queue = {:sbroker_codel_queue, {out, target * 1_000, interval * 1_000, drop, size}}
    worker_queue = {:sbroker_drop_queue, {:out_r, :drop, :infinity}}

    {:ok, {client_queue, worker_queue, 100}}
  end
end
