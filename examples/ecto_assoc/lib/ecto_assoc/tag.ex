defmodule EctoAssoc.Tag do
  use Ecto.Schema

  schema "tags" do
    field :name, :string
    many_to_many :posts, EctoAssoc.Post, join_through: "posts_tags"
  end
end
