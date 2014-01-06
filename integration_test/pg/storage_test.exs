defmodule Ecto.Integration.StorageTest do
  use Ecto.Integration.Postgres.Case

  alias Ecto.Adapters.Postgres
 
  defmodule NormalRepo do
    use Ecto.Repo, adapter: Ecto.Adapters.Postgres
    def url, do: "ecto://postgres:postgres@localhost/storage_mgt"
  end

  defmodule WrongUserRepo do
    use Ecto.Repo, adapter: Ecto.Adapters.Postgres
    def url, do: "ecto://random123:user456@localhost/storage_mgt"
  end

  test "storage up (twice in a row)" do 
    assert Postgres.storage_up(NormalRepo) == :ok
    assert Postgres.storage_up(NormalRepo) == { :error, :already_up }
 
    #Clean-up for this test
    Mix.Shell.cmd(%s(psql -U postgres -c "DROP DATABASE IF EXISTS storage_mgt;"), fn(_) -> end)   
  end

  test "storage up (wrong credentials)" do 
    { :error, error } = Postgres.storage_up(WrongUserRepo)
    assert error =~ %r(password authentication) 
  end
end