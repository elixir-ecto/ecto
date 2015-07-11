defmodule Simple.Repo.Migrations.CreateCityAndCountry do
  use Ecto.Migration

  def up do

    # here we remove `:city` field and add the
    # `:city_id` field to the weather table that
    # was created in the previous migration.
    # Then we add the :cities and :countries tables.

    alter table(:weather) do
      remove :city
      add :city_id, :integer
    end
    create index(:weather, [:city_id])


    create table(:cities) do
      add :name, :string, size: 40, null: false
      add :country_id, :integer
    end
    create index(:cities, [:country_id])


    create table(:countries) do
      add :name, :string, size: 40, null: false
    end
  end

  def down do
    drop index(:weather, [:city_id])
    drop index(:cities,  [:country_id])

    alter table(:weather) do
      remove :city_id
      add :city, :string, size: 40
    end

    drop table(:cities)
    drop table(:countries)

  end
end
