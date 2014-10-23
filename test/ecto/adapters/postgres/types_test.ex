defmodule Ecto.Adapters.Postgres.TypesTest do
  use ExUnit.Case, async: true

  test "it can decode hstore into a map" do
    result_map = Ecto.Adapters.Postgres.Hstore.decode ~s("name"=>"Frank","bubbles"=>"seven")
    assert result_map == %{"name" => "Frank", "bubbles" => "seven"}
  end

  test "it can decode special hstore values" do
    result_map = Ecto.Adapters.Postgres.Hstore.decode ~s("limit"=>NULL,"chillin"=>"true","fratty"=>"false")
    assert result_map == %{
      "limit" => nil,
      "chillin"=> true,
      "fratty"=> false
    }
  end

  test "it can decode hstore integers" do
    result_map = Ecto.Adapters.Postgres.Hstore.decode ~s("bubbles"=>"7")
    assert result_map == %{"bubbles" => 7}
  end

  test "it can decode hstore floats" do
    result_map = Ecto.Adapters.Postgres.Hstore.decode ~s("bubbles"=>"7.5")
    assert result_map == %{"bubbles" => 7.5}
  end


  test "it can encode a map into hstore" do
    input_map = Ecto.Adapters.Postgres.Hstore.encode %{"name" => "Frank", "bubbles" => "seven"}
    assert input_map == ~s("bubbles"=>"seven","name"=>"Frank")
  end

  test "it can encode a map with nils and booleans into hstore" do
    input_map = Ecto.Adapters.Postgres.Hstore.encode(%{
      "limit" => nil,
      "chillin"=> true,
      "fratty"=> false
    })
    assert input_map == ~s("chillin"=>"true","fratty"=>"false","limit"=>NULL)
  end

  test "it can encode integers and floats as hstore" do
    input_map = Ecto.Adapters.Postgres.Hstore.encode %{
      "bubbles" => 7,
      "fragmentation grenades" => 3.5
    }
    assert input_map == ~s("bubbles"=>"7","fragmentation grenades"=>"3.5")
  end


end
