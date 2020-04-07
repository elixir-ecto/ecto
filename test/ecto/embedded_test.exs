defmodule Ecto.EmbeddedTest do
  use ExUnit.Case, async: true

  doctest Ecto.Embedded
  alias Ecto.Embedded

  defmodule Author do
    use Ecto.Schema

    schema "authors" do
      field :name, :string
      embeds_one :profile, Profile, on_replace: :delete
      embeds_one :post, Post
      embeds_many :posts, Post, on_replace: :delete
    end
  end

  defmodule MySchemaWithUuid do
    use Ecto.Schema

    schema "my_schema" do
      field :uuid, Ecto.UUID

      embeds_one :author, Ecto.EmbeddedTest.Author
      embeds_many :authors, Ecto.EmbeddedTest.Author
    end
  end

  test "__schema__" do
    assert Author.__schema__(:embeds) ==
      [:profile, :post, :posts]

    assert Author.__schema__(:embed, :profile) ==
      %Embedded{field: :profile, cardinality: :one, owner: Author, on_replace: :delete, related: Profile}

    assert Author.__schema__(:embed, :posts) ==
      %Embedded{field: :posts, cardinality: :many, owner: Author, on_replace: :delete, related: Post}
  end

  test "embedded_load/3" do
    uuid = Ecto.UUID.generate()

    assert %MySchemaWithUuid{uuid: ^uuid} =
             Ecto.embedded_load(MySchemaWithUuid, %{"uuid" => uuid}, :json)

    assert %MySchemaWithUuid{uuid: ^uuid} =
             Ecto.embedded_load(MySchemaWithUuid, %{uuid: uuid}, :json)

    assert %MySchemaWithUuid{uuid: nil} =
             Ecto.embedded_load(MySchemaWithUuid, %{"uuid" => nil}, :json)

    assert %MySchemaWithUuid{uuid: ^uuid, author: %Author{name: "Bob"}} =
             Ecto.embedded_load(MySchemaWithUuid, %{"uuid" => uuid, "author" => %{"name" => "Bob"}}, :json)

    assert %MySchemaWithUuid{uuid: ^uuid, authors: [%Author{}]} =
             Ecto.embedded_load(MySchemaWithUuid, %{"uuid" => uuid, "authors" => [%{}]}, :json)

    assert_raise ArgumentError,
                 ~s[cannot load `"ABC"` as type Ecto.UUID for field `uuid` in schema Ecto.EmbeddedTest.MySchemaWithUuid],
                 fn ->
                   Ecto.embedded_load(MySchemaWithUuid, %{"uuid" => "ABC"}, :json)
                 end
  end

  test "embedded_dump/2" do
    uuid = Ecto.UUID.generate()

    assert %{uuid: ^uuid} = Ecto.embedded_dump(%MySchemaWithUuid{uuid: uuid}, :json)

    struct = %MySchemaWithUuid{uuid: uuid, authors: [
      %Author{name: "Bob"},
      %Author{name: "Alice"}
    ]}
    dumped = Ecto.embedded_dump(struct, :json)
    assert not Map.has_key?(dumped, :__struct__)
    assert [author1 | _] = dumped.authors
    assert not Map.has_key?(author1, :__struct__)
    assert not Map.has_key?(author1, :__meta__)
  end
end
