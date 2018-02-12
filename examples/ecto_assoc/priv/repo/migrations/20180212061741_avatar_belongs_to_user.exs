defmodule EctoAssoc.Repo.Migrations.AvatarBelongsToUser do
  use Ecto.Migration

  def change do
    alter table(:avatars) do
      add :user_id, references(:users)
    end
  end
end
