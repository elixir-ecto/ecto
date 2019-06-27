defmodule Botany.Repo.Migrations.TaxonIdentification do
  use Ecto.Migration

  def up do
    import Ecto.Query
    alter table(:accession) do
      add :taxon_id, references(:taxon)
    end

    flush()

    q = from(a in "accession",
      where: fragment("substring(? from '\\w+\.$') != 'sp.'", a.species),
      update: [set: [taxon_id: fragment(
                  ~S"(select id from taxon where epithet=substring(? from '\w+$') and parent_id=(select id from taxon where epithet=substring(? from '^\w+')))", 
                  a.species, a.species)]])
    Botany.Repo.update_all(q, [])
    q = from(a in "accession",
      where: fragment("substring(? from '\\w+\.$') = 'sp.'", a.species),
      update: [set: [taxon_id: fragment("(select id from taxon where epithet=substring(? from '^\\w+'))", a.species)]])
    Botany.Repo.update_all(q, [])

    alter table(:accession) do
      remove :species
    end
  end
end
