defmodule Ecto.Adapters.SQLTest do
  use ExUnit.Case, async: true

  defmodule Adapter do
    use Ecto.Adapters.SQL
    def supports_ddl_transaction?, do: false
  end

  Application.put_env(:ecto, __MODULE__.Repo, adapter: Adapter)

  defmodule Repo do
    use Ecto.Repo, otp_app: :ecto
  end

  Application.put_env(:ecto, __MODULE__.RepoWithTimeout, adapter: Adapter, pool_timeout: 3000, timeout: 1500)

  defmodule RepoWithTimeout do
    use Ecto.Repo, otp_app: :ecto
  end

  test "stores __pool__ metadata" do
    assert Repo.__pool__ == {Ecto.Pools.Poolboy, Repo.Pool, 5000, 15000}
    assert RepoWithTimeout.__pool__ ==
      {Ecto.Pools.Poolboy, RepoWithTimeout.Pool, 3000, 1500}
  end
end
