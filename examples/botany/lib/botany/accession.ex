defmodule Botany.Accession do
  use Ecto.Schema

  schema "accession" do
    field :code, :string
    many_to_many :taxa, Botany.Accession, join_through: "verification"
    has_many :verifications, Botany.Verification
    has_many :plants, Botany.Plant
    field :orig_quantity, :integer
    field :bought_on, :utc_datetime
    field :bought_from, :string
  end
end
