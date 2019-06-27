defmodule Botany.Plant do
  use Ecto.Schema

  schema "plant" do
    belongs_to :location, Botany.Location
    belongs_to :accession, Botany.Accession
    field :code, :string
    field :quantity, :integer
  end
end
