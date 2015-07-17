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

  @binary_id %{binary_id: Ecto.UUID, adapter: __MODULE__}

  def load_embed(value, _model, _types, _id_types) do
    Enum.into(value, %{}, fn {k, v} -> {String.to_atom(k), v} end)
  end

  test "load!" do
    data = %{"id" => 123, "name" => "michal", "count" => Decimal.new(5),
             "array" => ["array"], "uuid" => @uuid_binary,
             "embed" => %{"type" => "one", "id" => @uuid_string}}
    loaded = Serializer.load!(Model, nil, "mymodel", data, @binary_id)

    assert loaded.name  == "michal"
    assert loaded.count == Decimal.new(5)
    assert loaded.array == ["array"]
    assert loaded.uuid  == @uuid_string
    assert %{type: "one", id: @uuid_string} = loaded.embed
  end
end
