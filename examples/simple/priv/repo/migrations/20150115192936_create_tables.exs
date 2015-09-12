defmodule Repo.CreateTables do
  use Ecto.Migration

  def up do
    create table(:weather) do
      add :city_id, :integer
      add :wdate,   :date
      add :temp_lo, :integer
      add :temp_hi, :integer
      add :prcp,    :float
      timestamps
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
    drop table(:weather)
    drop table(:cities)
    drop table(:countries)
  end
end
