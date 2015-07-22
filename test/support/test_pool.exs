defmodule Ecto.TestPool do
  alias Ecto.Pool

  @pool_opts Application.get_env(:ecto, :pool_opts, [pool: Ecto.Pools.Poolboy])
  @pool @pool_opts[:pool]

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
    @pool.start_link(Connection, [pool_size: 1] ++ @pool_opts ++ opts)
  end

  def transaction(pool, timeout, fun) do
    Pool.transaction(@pool, pool, timeout, fun)
  end

  defdelegate break(ref, timeout), to: Pool

  def run(pool, timeout, fun) do
    Pool.run(@pool, pool, timeout, fun)
  end
end
