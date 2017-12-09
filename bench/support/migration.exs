defmodule Ecto.Bench.Migration do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string
      add :email, :string
      timestamps()
    end
  end
end
