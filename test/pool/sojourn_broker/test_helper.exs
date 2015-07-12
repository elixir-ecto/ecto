Logger.configure(level: :info)
ExUnit.start

broker =
  case System.get_env("MIX_ENV") do
    "sojourn_timeout" -> Ecto.Pools.SojournBroker.Timeout
    "sojourn_codel"   -> Ecto.Pools.SojournBroker.CoDel
  end

Application.put_env(:ecto, :pool_opts, pool: Ecto.Pools.SojournBroker, broker: broker)

# Load support files
Code.require_file "../../support/test_pool.exs", __DIR__