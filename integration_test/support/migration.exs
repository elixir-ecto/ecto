defmodule Ecto.Integration.Migration do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :title, :string, size: 100
      add :counter, :integer, default: 10
      add :text, :binary
      add :uuid, :uuid
      add :public, :boolean
      add :cost, :decimal, precision: 2, scale: 1
      add :visits, :integer
      add :intensity, :float
      timestamps
    end

    create table(:users) do
      add :name, :text
      add :custom_id, :uuid
    end

    create table(:permalinks) do
      add :url
      add :post_id, :integer
    end

    create table(:comments) do
      add :text, :string, size: 100
      add :posted, :datetime
      add :post_id, references(:posts)
      add :author_id, references(:users)
    end

    create table(:customs, primary_key: false) do
      add :foo, :uuid, primary_key: true
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
