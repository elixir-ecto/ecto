defmodule Botany.Repo.Migrations.IntroduceVerifications do
  use Ecto.Migration

  def up do
    import Ecto.Query
    create table(:verification) do
      add :accession_id, references(:accession)
      add :taxon_id, references(:taxon)
      add :verifier, :string
      add :level, :integer
      add :timestamp, :utc_datetime
    end

    flush()

    utc_now = DateTime.utc_now()
    veris = from(a in "accession", select: %{accession_id: a.id, taxon_id: a.taxon_id}) |>
      Botany.Repo.all |>
      Enum.map(&(&1 |>
            Map.put(:verifier, "Elixir") |>
            Map.put(:level, 0) |>
            Map.put(:timestamp, utc_now)))
    Botany.Repo.insert_all("verification", veris)
    
    alter table(:accession) do
      remove :taxon_id
    end
  end

  def down do
    alter table(:accession) do
      add :taxon_id, references(:taxon)
    end
    flush()
    ## move one of the verification links to the accession table
    drop table(:verification)
  end
end
