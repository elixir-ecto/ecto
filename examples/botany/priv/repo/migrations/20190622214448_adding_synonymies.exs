defmodule Botany.Repo.Migrations.AddingSynonymies do
  use Ecto.Migration

  def change do
    alter table("taxon") do
      add :accepted_id, references(:taxon)
    end
  end
end
