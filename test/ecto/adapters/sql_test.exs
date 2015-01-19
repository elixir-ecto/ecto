defmodule Ecto.Adapters.SQLTest do
  use ExUnit.Case, async: true

  defmodule Adapter do
    use Ecto.Adapters.SQL
  end

  defmodule Repo do
    use Ecto.Repo, adapter: Adapter, otp_app: :ecto
  end

  test "stores __pool__ metadata" do
    assert Repo.__pool__ == Repo.Pool
  end
end
