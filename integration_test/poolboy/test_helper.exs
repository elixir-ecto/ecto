Logger.configure(level: :info)
ExUnit.start


# Load support files
Code.require_file "../support/pool.exs", __DIR__
Code.require_file "../support/connection.exs", __DIR__

defmodule Ecto.Integration.TestPool do
  use Ecto.Integration.Pool, Ecto.Adapters.Poolboy
end
