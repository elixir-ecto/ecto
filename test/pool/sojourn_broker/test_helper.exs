Logger.configure(level: :info)
ExUnit.start

# Load support files
Application.put_env(:ecto, :pool, Ecto.Pools.SojournBroker)
Ecto.Adapters.SQL.DBConnIdMap.start_link # Hackety Hack
Code.require_file "../../support/test_pool.exs", __DIR__
Code.require_file "../../support/test_repo.exs", __DIR__
