Logger.configure(level: :info)
ExUnit.start

# Load support files
Application.put_env(:ecto, :pool, Ecto.Adapters.Poolboy)
Code.require_file "../../support/test_pool.exs", __DIR__
