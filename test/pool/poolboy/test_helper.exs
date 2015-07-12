Logger.configure(level: :info)
ExUnit.start

# Load support files
Application.put_env(:ecto, :pool_opts, pool: Ecto.Pools.Poolboy)
Code.require_file "../../support/test_pool.exs", __DIR__
