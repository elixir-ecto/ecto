defmodule Ecto.Integration.Connection do
  @behaviour Ecto.Adapters.Connection
  def connect(_opts) do
    Agent.start_link(fn -> [] end)
  end

  def disconnect(conn) do
    Agent.stop(conn)
  end
end
