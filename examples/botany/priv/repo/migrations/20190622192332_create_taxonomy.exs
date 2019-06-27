defmodule Botany.Repo.Migrations.CreateTaxonomy do
  use Ecto.Migration

  def change do
    create table(:rank) do
      add :name, :string
    end

    create table(:taxon) do
      add :epithet, :string
      add :authorship, :string
      add :rank_id, references(:rank)
      add :parent_id, references(:taxon)
    end
  end
end
