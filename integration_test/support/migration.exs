defmodule Ecto.Integration.Migration do
  use Ecto.Migration

  def up do
    create table(:posts) do
      add :title, :string, size: 100
      add :counter, :integer, default: 10
      add :text, :string
      add :tags, {:array, :text}
      add :bin, :binary
      add :uuid, :uuid
      add :cost, :decimal, precision: 2, scale: 2
      timestamps
    end

    create table(:users) do
      add :name, :text
    end

    create table(:permalinks) do
      add :url
      add :post_id, :integer
    end

    create table(:comments) do
      add :text, :string, size: 100
      add :posted, :datetime
      add :day, :date
      add :time, :time
      add :bytes, :binary
      add :post_id, references(:posts)
      add :author_id, references(:users)
    end

    create table(:customs, primary_key: false) do
      add :foo, :uuid, primary_key: true
    end

    create table(:barebones) do
      add :text, :text
    end

    create table(:transactions) do
      add :text, :text
    end

    create table(:lock_counters) do
      add :count, :integer
    end

    create table(:migrations_test) do
      add :num, :integer
    end
  end
end
