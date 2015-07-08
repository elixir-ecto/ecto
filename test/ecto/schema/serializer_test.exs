defmodule Ecto.Schema.SerializerTest do
  use ExUnit.Case, async: true

  defmodule Embed do
    use Ecto.Model

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
             "embed" => %{"type" => "one"}}
    loaded = Serializer.load!(Model, "mymodel", data, %{})


    assert loaded.name  == "michal"
    assert loaded.count == Decimal.new(5)
    assert loaded.array == ["array"]
    assert loaded.uuid  == @uuid_string
    assert %Embed{type: "one"} = loaded.embed
  end

  test "dump!" do
    embed = %Embed{type: "one"}
    model = %Model{id: 123, name: "michal", count: Decimal.new(5), array: ["array"],
                   uuid: @uuid_string, embed: embed}

    dumped_uuid = %Ecto.Query.Tagged{tag: nil, type: :uuid, value: @uuid_binary}

    dumped = Serializer.dump!(model, %{})
    assert dumped == %{id: 123, name: "michal", count: Decimal.new(5),
                       array: ["array"], embed: %{type: "one"}, uuid: dumped_uuid}

    dumpled = Serializer.dump!(model, %{}, skip_pk: true)
    assert dumpled == %{name: "michal", count: Decimal.new(5),
                        array: ["array"], embed: %{type: "one"}, uuid: dumped_uuid}
  end
end
