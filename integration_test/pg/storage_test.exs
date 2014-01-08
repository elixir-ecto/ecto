defmodule Ecto.Integration.StorageTest do
  use Ecto.Integration.Postgres.Case

  alias Ecto.Adapters.Postgres

  test "storage up (twice in a row)" do
    assert Postgres.storage_up([database: "storage_mgt",
                                username: "postgres",
                                password: "postgres",
                                hostname: "localhost"]) == :ok

    assert Postgres.storage_up([database: "storage_mgt",
                                username: "postgres",
                                password: "postgres",
                                hostname: "localhost"]) == { :error, :already_up }

    #Clean-up for this test
    System.cmd %s(psql -U postgres -c "DROP DATABASE IF EXISTS storage_mgt;")
  end

  test "storage up (wrong credentials)" do
    { :error, error } = Postgres.storage_up([database: "storage_mgt",
                                             username: "randomuser",
                                             password: "password1234",
                                             hostname: "localhost"])
    assert error =~ %r(password authentication)
  end
end