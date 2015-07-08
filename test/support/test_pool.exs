defmodule Ecto.TestPool do
  alias Ecto.Pool
  @pool Application.get_env(:ecto, :pool, Ecto.Pools.Poolboy)

  defmodule Connection do
    @behaviour Ecto.Adapters.Connection

    def connect(opts) do
      trap = Keyword.get(opts, :trap_exit, false)
      Agent.start_link(fn ->
        Process.flag(:trap_exit, trap)
        []
      end)
    end
  end

  def start_link(opts) do
    @pool.start_link(Connection, [size: 1] ++ opts)
  end

  def transaction(pool, timeout, fun) do
    Pool.transaction(@pool, pool, timeout, fun)
  end

  defdelegate break(ref, timeout), to: Pool

  def run(pool, timeout, fun) do
    Pool.run(@pool, pool, timeout, fun)
  end
end
