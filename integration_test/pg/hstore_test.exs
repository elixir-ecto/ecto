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
    Postgres.query(TestRepo, "CREATE TABLE IF NOT EXISTS hstore_test(id serial primary key, data hstore)", [])
    :ok
  end

  test "it can add data to the database" do
    test_data = %{ "name" => "frank", "bubbles" => 7 }
    %HstoreTestModel{id: id} =  %HstoreTestModel{data: test_data} |> TestRepo.insert
    assert is_integer(id)
    saved_model = TestRepo.get(HstoreTestModel, id)
    assert saved_model.data == test_data
  end

  test "it can convert booleans and nil values" do
    test_data = %{ "yes" => true, "nope!" => false, "invisible" => nil }
    %HstoreTestModel{id: id} =  %HstoreTestModel{data: test_data} |> TestRepo.insert
    assert is_integer(id)
    saved_model = TestRepo.get(HstoreTestModel, id)
    assert saved_model.data == test_data
  end

  test "it can convert keys and values that are atoms" do
    test_data = %{ p: :proton, e: :electron, n: :nucleus }
    %HstoreTestModel{id: id} =  %HstoreTestModel{data: test_data} |> TestRepo.insert
    assert is_integer(id)
    saved_model = TestRepo.get(HstoreTestModel, id)
    assert saved_model.data == %{ "e" => "electron", "n" => "nucleus", "p" => "proton" }
  end

  test "it can handle keys with spaces in them" do
    test_data = %{ "One Space" => 1, "Two  Spaces" => 2 }
    %HstoreTestModel{id: id} =  %HstoreTestModel{data: test_data} |> TestRepo.insert
    assert is_integer(id)
    saved_model = TestRepo.get(HstoreTestModel, id)
    assert saved_model.data == test_data
  end
end
