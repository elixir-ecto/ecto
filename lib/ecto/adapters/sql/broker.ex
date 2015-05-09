defmodule Ecto.Adapters.SQL.Broker do

  @behaviour :sbroker

  def checkout(broker) do
    case :sbroker.ask(broker) do
      {:go, _, worker, _, _} -> worker
      {:drop, _} = drop      -> exit({drop, {__MODULE__, :checkout, [broker]}})
    end
  end

  def checkin(broker, tag) do
    _ = :sbroker.async_ask_r(broker, tag)
    :ok
  end

  def cancel(broker, ref) do
    :sbroker.cancel(broker, ref)
  end

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    :sbroker.start_link({:local, name}, __MODULE__, opts)
  end

  def init(opts) do
    client_queue = Keyword.fetch!(opts, :client_queue)
    worker_queue = Keyword.fetch!(opts, :worker_queue)
    queue_interval = Keyword.fetch!(opts, :queue_interval)

    {:ok, {client_queue, worker_queue, queue_interval}}
  end
end
