defmodule Ecto.Integration.HstoreTest do
  use Ecto.Integration.Postgres.Case

  alias Ecto.Adapters.Postgres

  defmodule HstoreTestModel do
    use Ecto.Model
    schema "hstore_test" do
      field :data, :hstore
    end
  end

  setup do
    Postgres.query(TestRepo, "CREATE EXTENSION IF NOT EXISTS hstore", [])
    Postgres.query(TestRepo, "CREATE TABLE IF NOT EXISTS hstore_test(id serial primary key, data hstore)", [])
    :ok
  end

  test "it can add data to the database" do
    test_data = %{ "name" => "frank", "bubbles" => 7 }
    %HstoreTestModel{id: id} =  %HstoreTestModel{data: test_data} |> TestRepo.insert
    assert is_integer(id)
    saved_model = Postgres.query(TestRepo, "SELECT * FROM hstore_test WHERE id = $1", [id])
    assert saved_model.data == test_data
  end
end
