defmodule Ecto.PoolSup do
  @moduledoc false

  use Supervisor.Behaviour

  def start_link do
    :supervisor.start_link({ :local, __MODULE__ }, __MODULE__, [])
  end

  def start_child(args) do
    :supervisor.start_child(__MODULE__, args)
  end

  def init([]) do
    tree = [ worker(:poolboy, []) ]
    supervise(tree, strategy: :simple_one_for_one)
  end
end
