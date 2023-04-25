defmodule Ecto.EmbeddedTest do
  use ExUnit.Case, async: true

  doctest Ecto.Embedded
  alias Ecto.Embedded

  defmodule Post do
    use Ecto.Schema

    embedded_schema do
      field :title
    end
  end

  defmodule Author do
    use Ecto.Schema

    embedded_schema do
      field :name, :string
      embeds_one :profile, Profile, on_replace: :delete
      embeds_one :post, Post
      embeds_many :posts, Post, on_replace: :delete
    end
  end

  defmodule UUIDSchema do
    use Ecto.Schema

    embedded_schema do
      field :uuid, Ecto.UUID

      embeds_one :author, Ecto.EmbeddedTest.Author
      embeds_many :authors, Ecto.EmbeddedTest.Author
    end
  end

  defmodule OneOfSchema do
    use Ecto.Schema

    embedded_schema do
      embeds_one :thing, {:one_of, author: Author, post: Post}
      embeds_many :things, {:one_of, author: Author, post: Post}
    end
  end

  describe "one of embeds" do
    test "__schema__" do
      assert OneOfSchema.__schema__(:embeds) == [:thing, :things]

      assert OneOfSchema.__schema__(:embed, :thing) ==
        %Embedded{field: :thing, cardinality: :one, owner: OneOfSchema, related: {:one_of, author: Author, post: Post}}

      assert OneOfSchema.__schema__(:embed, :things) ==
        %Embedded{field: :things, cardinality: :many, owner: OneOfSchema, related: {:one_of, author: Author, post: Post}}
    end

    test "embedded_load/3" do
      assert %OneOfSchema{thing: %Post{title: "Title"}} =
              Ecto.embedded_load(OneOfSchema, %{"thing" => %{"type" => "post", "data" => %{"title" => "Title"}}}, :json)

      assert %OneOfSchema{thing: %Post{title: "Title"}} =
              Ecto.embedded_load(OneOfSchema, %{thing: %{type: "post", data: %{title: "Title"}}}, :json)

      assert %OneOfSchema{thing: %Post{title: "Title"}} =
              Ecto.embedded_load(OneOfSchema, %{thing: %{type: :post, data: %{title: "Title"}}}, :json)

      assert %OneOfSchema{things: [%Post{title: "Title"}, %Author{name: "Name"}]} =
              Ecto.embedded_load(OneOfSchema, %{"things" => [
                %{"type" => "post", "data" => %{"title" => "Title"}},
                %{"type" => "author", "data" => %{"name" => "Name"}}
              ]}, :json)

      assert %OneOfSchema{things: [%Post{title: "Title"}, %Author{name: "Name"}]} =
              Ecto.embedded_load(OneOfSchema, %{things: [
                %{type: "post", data: %{title: "Title"}},
                %{type: "author", data: %{name: "Name"}}
              ]}, :json)
    end

    test "embedded_dump/2" do
      struct = %OneOfSchema{things: [%Post{title: "Title"}, %Author{name: "Name"}]}

      dumped = Ecto.embedded_dump(struct, :json)
      assert not Map.has_key?(dumped, :__struct__)
      assert [%{type: :post, data: %{title: "Title"}} = post | _] = dumped.things
      assert not Map.has_key?(post, :__struct__)
      assert not Map.has_key?(post, :__meta__)

      assert_raise ArgumentError,
        ~s[cannot dump embed `things`, expected a list of Ecto.EmbeddedTest.Author or Ecto.EmbeddedTest.Post struct values but got: :something],
        fn ->
          Ecto.embedded_dump(%OneOfSchema{things: [:something]}, :json)
        end
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

    assert %UUIDSchema{uuid: ^uuid} =
             Ecto.embedded_load(UUIDSchema, %{"uuid" => uuid}, :json)

    assert %UUIDSchema{uuid: ^uuid} =
             Ecto.embedded_load(UUIDSchema, %{uuid: uuid}, :json)

    assert %UUIDSchema{uuid: nil} =
             Ecto.embedded_load(UUIDSchema, %{"uuid" => nil}, :json)

    assert %UUIDSchema{uuid: ^uuid, author: %Author{name: "Bob"}} =
             Ecto.embedded_load(UUIDSchema, %{"uuid" => uuid, "author" => %{"name" => "Bob"}}, :json)

    assert %UUIDSchema{uuid: ^uuid, authors: [%Author{}]} =
             Ecto.embedded_load(UUIDSchema, %{"uuid" => uuid, "authors" => [%{}]}, :json)

    assert_raise ArgumentError,
                 ~s[cannot load `"ABC"` as type Ecto.UUID for field `uuid` in schema Ecto.EmbeddedTest.UUIDSchema],
                 fn ->
                   Ecto.embedded_load(UUIDSchema, %{"uuid" => "ABC"}, :json)
                 end
  end

  test "embedded_dump/2" do
    uuid = Ecto.UUID.generate()

    assert %{uuid: ^uuid} = Ecto.embedded_dump(%UUIDSchema{uuid: uuid}, :json)

    struct = %UUIDSchema{uuid: uuid, authors: [
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
