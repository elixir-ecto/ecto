defmodule Ecto.Integration.Migration do
  use Ecto.Migration

  def change do
    create table(:users, comment: "users table") do
      add :name, :text, comment: "name column"
      add :custom_id, :uuid
      timestamps()
    end

    create table(:posts) do
      add :title, :string, size: 100
      add :counter, :integer
      add :text, :binary
      add :bid, :binary_id
      add :uuid, :uuid
      add :meta, :map
      add :links, {:map, :string}
      add :public, :boolean
      add :cost, :decimal, precision: 2, scale: 1
      add :visits, :integer
      add :intensity, :float
      add :author_id, :integer
      add :posted, :date
      timestamps null: true
    end

    create table(:posts_users, primary_key: false) do
      add :post_id, references(:posts)
      add :user_id, references(:users)
    end

    create table(:posts_users_pk) do
      add :post_id, references(:posts)
      add :user_id, references(:users)
      timestamps()
    end

    # Add a unique index on uuid. We use this
    # to verify the behaviour that the index
    # only matters if the UUID column is not NULL.
    create unique_index(:posts, [:uuid], comment: "posts index")

    create table(:permalinks) do
      add :url, :string
      add :post_id, references(:posts)
      add :user_id, references(:users)
    end

    create table(:comments) do
      add :text, :string, size: 100
      add :lock_version, :integer, default: 1
      add :post_id, references(:posts)
      add :author_id, references(:users)
    end

    create table(:customs, primary_key: false) do
      add :bid, :binary_id, primary_key: true
      add :uuid, :uuid
    end

    create unique_index(:customs, [:uuid])

    create table(:customs_customs, primary_key: false) do
      add :custom_id1, references(:customs, column: :bid, type: :binary_id)
      add :custom_id2, references(:customs, column: :bid, type: :binary_id)
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

    create table(:orders) do
      add :item, :map
      add :comment_id, references(:comments)
    end

    unless :array_type in ExUnit.configuration[:exclude] do
      create table(:tags) do
        add :ints,  {:array, :integer}
        add :uuids, {:array, :uuid}, default: []
        add :items, {:array, :map}
      end
    end

    create table(:composite_pk, primary_key: false) do
      add :a, :integer, primary_key: true
      add :b, :integer, primary_key: true
      add :name, :string
    end

    create table(:posts_users_composite_pk) do
      add :post_id, references(:posts), primary_key: true
      add :user_id, references(:users), primary_key: true
      timestamps()
    end

    create unique_index(:posts_users_composite_pk, [:post_id, :user_id])
  end
end
