defmodule Ecto.Integration.PortTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.Postgres.Connection

  test "port as integer" do
    {mode, _} = Connection.connect([port: 5432, database: "postgres"])
    assert mode == :ok
  end

  test "port as string" do
    {mode, _} = Connection.connect([port: "5432", database: "postgres"])
    assert mode == :ok
  end

end
