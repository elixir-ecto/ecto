defmodule EctoAssoc.Post do
  use Ecto.Schema

  schema "posts" do
    field :header, :string
    field :body, :string
    belongs_to :user, EctoAssoc.User
    many_to_many :tags, EctoAssoc.Tag, join_through: "posts_tags", on_replace: :delete
  end
end
