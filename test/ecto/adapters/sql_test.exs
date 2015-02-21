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

  Application.put_env(:ecto, __MODULE__.RepoWithTimeout, adapter: Adapter)

  defmodule RepoWithTimeout do
    use Ecto.Repo, otp_app: :ecto
    Application.put_env(:ecto, __MODULE__, timeout: 1500)
  end

  test "stores __pool__ metadata" do
    assert Repo.__pool__ == {Repo.Pool, 5000}
    assert RepoWithTimeout.__pool__ == {RepoWithTimeout.Pool, 1500}
  end
end
