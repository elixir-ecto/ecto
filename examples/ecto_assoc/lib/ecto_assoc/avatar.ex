defmodule EctoAssoc.Avatar do
  use Ecto.Schema

  schema "avatars" do
    field :nick_name, :string
    field :pic_url, :string
    belongs_to :user, EctoAssoc.User
  end
end
