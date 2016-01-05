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
    assert {Repo.Pool, opts} = Repo.__pool__
    assert Keyword.fetch!(opts, :pool_timeout) == 5_000
    assert Keyword.fetch!(opts, :timeout) == 15_000

    assert {RepoWithTimeout.Pool, opts} = RepoWithTimeout.__pool__
    assert Keyword.fetch!(opts, :pool_timeout) == 3_000
    assert Keyword.fetch!(opts, :timeout) == 1_500
  end
end
