defmodule Ecto.Pools.SojournBroker.Timeout do
  @moduledoc """
  Timeout based broker.

  Drops requests waiting for a connection after a timeout. See
  `:sbroker_timeout_queue` for more information.

  ### Options

    * `:queue_timeout` - The amount of time in milliseconds to wait in queue (default: `5_000`)
    * `:queue_out` - Either `:out` for a FIFO queue or `:out_r` for a LIFO queue (default: `:out`)
    * `:queue_drop` - Either `:drop` for head drop on max size or `:drop_r` for tail drop (default: `:drop`)
    * `:queue_size` - The maximum size of the queue (default: `128`)

  """

  if Code.ensure_loaded?(:sbroker) do
    @behaviour :sbroker
  end

  @doc false
  def init(opts) do
    out     = Keyword.get(opts, :queue_out, :out)
    timeout = Keyword.get(opts, :queue_timeout, 5_000)
    drop    = Keyword.get(opts, :queue_drop, :drop)
    size    = Keyword.get(opts, :queue_size, 128)

    if timeout != :infinity, do: timeout = timeout * 1_000
    client_queue = {:sbroker_timeout_queue, {out, timeout, drop, size}}
    worker_queue = {:sbroker_drop_queue, {:out_r, :drop, :infinity}}

    {:ok, {client_queue, worker_queue, 100}}
  end
end
