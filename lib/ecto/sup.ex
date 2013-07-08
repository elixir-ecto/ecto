defmodule Ecto.Sup do
  @moduledoc false

  use Supervisor.Behaviour

  def start_link do
    :supervisor.start_link({ :local, __MODULE__ }, __MODULE__, [])
  end

  def init([]) do
    tree = [ supervisor(Ecto.PoolSup, []) ]
    supervise(tree, strategy: :one_for_all)
  end
end
