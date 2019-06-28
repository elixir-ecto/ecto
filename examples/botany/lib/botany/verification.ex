defmodule Botany.Verification do
  use Ecto.Schema

  schema "verification" do
    belongs_to :accession, Botany.Accession
    belongs_to :taxon, Botany.Taxon
    field :verifier, :string
    field :level, :integer
    field :timestamp, :utc_datetime
  end
end
