defmodule Ecto.Schema.SerializerTest do
  use ExUnit.Case, async: true

  defmodule Embed do
    use Ecto.Model

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "" do
      field :type, :string
    end
  end

  defmodule Model do
    use Ecto.Model

    schema "mymodel" do
      field :name,  :string
      field :count, :decimal
      field :array, {:array, :string}
      field :uuid, Ecto.UUID
      embeds_one :embed, Embed
    end
  end

  alias Ecto.Schema.Serializer

  @uuid_string "bfe0888c-5c59-4bb3-adfd-71f0b85d3db7"
  @uuid_binary <<191, 224, 136, 140, 92, 89, 75, 179, 173, 253, 113, 240, 184, 93, 61, 183>>

  test "load!" do
    data = %{"id" => 123, "name" => "michal", "count" => Decimal.new(5),
             "array" => ["array"], "uuid" => @uuid_binary,
             "embed" => %{"type" => "one", "id" => @uuid_binary}}
    loaded = Serializer.load!(Model, nil, "mymodel", data, &Ecto.TestAdapter.load/2)

    assert loaded.name  == "michal"
    assert loaded.count == Decimal.new(5)
    assert loaded.array == ["array"]
    assert loaded.uuid  == @uuid_string
    assert %{type: "one", id: @uuid_string} = loaded.embed
  end

  test "dump!" do
    embed = %Embed{type: "one", id: @uuid_string}
    model = %Model{id: 123, name: "michal", count: Decimal.new(5), array: ["array"],
                   uuid: @uuid_string, embed: embed}

    dumped_uuid = %Ecto.Query.Tagged{tag: nil, type: :uuid, value: @uuid_binary}

    dumped = Serializer.dump!(Model, model, &Ecto.TestAdapter.dump/2)
    assert dumped == %{name: "michal", count: Decimal.new(5), uuid: dumped_uuid,
                       array: ["array"], embed: %{type: "one", id: dumped_uuid}, id: 123}
  end
end
