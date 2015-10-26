defmodule Ecto.Migration.Manager.Supervisor do
  @doc """
  Starts the migration manager as a supervised process
  """
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      worker(Ecto.Migration.Manager, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end