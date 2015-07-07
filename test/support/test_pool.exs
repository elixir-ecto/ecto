defmodule Ecto.TestPool do
  alias Ecto.Pool
  @pool Application.get_env(:ecto, :pool, Ecto.Pools.Poolboy)

  defmodule Connection do
    use Ecto.Adapters.Connection

    def connect(_opts) do
      Agent.start_link(fn -> [] end)
    end

    def disconnect(conn) do
      Agent.stop(conn)
    end
  end

  def start_link(opts) do
    @pool.start_link(Connection, [size: 1] ++ opts)
  end

  def transaction(pool, timeout, fun) do
    Pool.transaction(@pool, pool, timeout, fun)
  end

  def run(pool, timeout, fun) do
    Pool.run(@pool, pool, timeout, fun)
  end

  defdelegate stop(pool), to: @pool
end
