defmodule Ecto.Integration.Migration do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :title, :string, size: 100
      add :counter, :integer, default: 10 # Do not propagate unless read_after_write
      add :text, :binary
      add :bid, :binary_id
      add :uuid, :uuid
      add :meta, :map
      add :public, :boolean
      add :cost, :decimal, precision: 2, scale: 1
      add :visits, :integer
      add :intensity, :float
      timestamps null: true
    end

    # Add a unique index on uuid. We use this
    # to verify the behaviour that the index
    # only matters if the UUID column is not NULL.
    create index(:posts, [:uuid], unique: true)

    create table(:users) do
      add :name, :text
      add :custom_id, :uuid
      timestamps
    end

    create table(:permalinks) do
      add :url
      add :post_id, :integer
    end

    create table(:comments) do
      add :text, :string, size: 100
      add :posted, :datetime
      add :lock_version, :integer, default: 1
      add :post_id, references(:posts, on_delete: :nilify_all)
      add :author_id, references(:users, on_delete: :delete_all)
    end

    create table(:customs, primary_key: false) do
      add :bid, :binary_id, primary_key: true
    end

    create table(:barebones) do
      add :num, :integer
    end

    create table(:transactions) do
      add :text, :text
    end

    create table(:lock_counters) do
      add :count, :integer
    end

    unless :array_type in ExUnit.configuration[:exclude] do
      create table(:tags) do
        add :ints, {:array, :integer}
        add :uuids, {:array, :uuid}
      end
    end
  end
end
