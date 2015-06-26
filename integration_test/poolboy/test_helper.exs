Logger.configure(level: :info)
ExUnit.start

# Load support files
Code.require_file "../pool/pool.exs", __DIR__

defmodule Ecto.Integration.TestPool do
  use Ecto.Integration.Pool, Ecto.Adapters.Poolboy
end
