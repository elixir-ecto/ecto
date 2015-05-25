defmodule Ecto.Integration.Migration do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :title, :string, size: 100
      add :counter, :integer, null: false, default: 10
      add :text, :binary
      add :uuid, :uuid
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

    create_users_table()
    create_permalinks_table()

    create table(:comments) do
      add :text, :string, size: 100
      add :posted, :datetime
      add :post_id, references(:posts)
      add :author_id, references(:users)
      timestamps
    end

    create table(:customs, primary_key: false) do
      add :uuid, :uuid, primary_key: true
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

  # For the users table, let's do a longer migration,
  # checking other migration features.
  #
  #     create table(:users) do
  #       add :name, :text
  #       add :custom_id, :uuid
  #     end
  #
  defp create_users_table do
    false = exists? table(:users)

    create table(:users) do
      add :name, :string
      add :to_be_removed, :string
    end

    true = exists? table(:users)

    alter table(:users) do
      modify :name, :text
      add :custom_id, :uuid
      remove :to_be_removed
    end

    index = index(:users, [:custom_id], unique: true)
    false = exists? index
    create index
    true = exists? index
    drop index
    false = exists? index
  end

  # For the permalinks table, let's create a table,
  # drop it, and get a new one.
  #
  #     create table(:permalinks) do
  #       add :url
  #       add :post_id, :integer
  #       add :lock_version, :integer, default: 1
  #     end
  #
  defp create_permalinks_table do
    create table(:permalinks) do
      add :to_be_removed
    end

    drop table(:permalinks)

    create table(:permalinks) do
      add :url
      add :post_id, :integer
      add :lock_version, :integer, default: 1
    end
  end
end
