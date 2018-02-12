defmodule EctoAssoc.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :header, :string
      add :body, :string
    end
  end
end
