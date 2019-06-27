defmodule Botany.Location do
  use Ecto.Schema

  schema "location" do
    has_many :plants, Botany.Plant  # backward link
    field :code, :string
    field :name, :string
    field :description, :string
  end
end
