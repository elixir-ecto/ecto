defmodule Botany.Repo.Migrations.PlantNameToAccessionCode do
  use Ecto.Migration

  def up do
    import Ecto.Query
    split_plant_create_accession = fn(plant) ->
      [_, acc_code, plt_code] = Regex.run(~r{(.*)\.([^\.]*)}, plant.name)
      query = from(a in "accession", select: [:id, :code], where: a.code==^acc_code)
      accession = case (query |> Botany.Repo.one()) do
                    nil -> (accession = %{id:         plant.id,
                                         bought_on:   plant.bought_on,
                                         bought_from: plant.bought_from,
                                         code:        acc_code,
                                         species:     plant.species,
                                         };
                      Botany.Repo.insert_all("accession", [accession]);
                      accession)
                    x -> x
                  end
      from(p in "plant", where: p.id==^plant.id, select: p.id) |>
        Botany.Repo.update_all(set: [accession_id: accession.id, code: plt_code])
    end

    create table(:accession) do
      add :code, :string
      add :species, :string
      add :taxon_id, references(:taxon)
      add :orig_quantity, :integer
      add :bought_on, :utc_datetime
      add :bought_from, :string
    end

    alter table(:plant) do
      add :code, :string
      add :accession_id, references(:accession)
    end

    flush()

    from("plant", select: [:id, :bought_on, :bought_from, :name, :species, :accession_id, :code]) |>
      Botany.Repo.all |>
      Enum.each(split_plant_create_accession)

    alter table(:plant) do
      remove :name
      remove :species
    end
  end

  def down do
    alter table(:plant) do
      add :name, :string
      add :species, :string
    end

    flush()

    alter table(:plant) do
      remove :code
      remove :accession_id
    end

    drop table(:accession)

  end
end
