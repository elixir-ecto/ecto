defmodule Botany.Taxon do
  use Ecto.Schema

  schema "taxon" do
    has_many :children, Botany.Taxon, foreign_key: :parent_id  # backward link
    field :epithet, :string
    field :authorship, :string
    belongs_to :parent, Botany.Taxon
    belongs_to :rank, Botany.Rank
    belongs_to :accepted, Botany.Taxon
    has_many :synonyms, Botany.Taxon, foreign_key: :accepted_id  # backward link
  end
end
