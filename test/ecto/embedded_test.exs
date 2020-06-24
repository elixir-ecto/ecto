defmodule Ecto.EmbeddedTest do
  use ExUnit.Case, async: true

  # doctest Ecto.Embedded
  # alias Ecto.Embedded

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

  test "__schema__" do
    assert Author.__schema__(:type, :profile) == {:parameterized, Ecto.Type.Embed, %{on_replace: :delete, type: Profile, field: :profile, schema: Ecto.EmbeddedTest.Author}}
    assert Author.__schema__(:type, :post) == {:parameterized, Ecto.Type.Embed, %{type: Post, field: :post, schema: Ecto.EmbeddedTest.Author, on_replace: :raise}}
    assert Author.__schema__(:type, :posts) == {:parameterized, Ecto.Type.EmbedMany, %{on_replace: :delete, type: Post, field: :posts, schema: Ecto.EmbeddedTest.Author}}
  end
end
