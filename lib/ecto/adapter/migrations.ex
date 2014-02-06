defmodule Ecto.Adapter.Migrations  do
  @moduledoc """
  Specifies the adapter migrations API.
  """

  use Behaviour

  @doc """
  Runs an up migration.

  It expects a repository, the migration version and the migration code.

  ## Examples

    migrate_up(Repo, 20080906120000, "CREATE TABLE users(id serial, name text)")

  """
  defcallback migrate_up(Ecto.Repo.t, integer, binary) :: :ok | :already_up | no_return

  @doc """
  Runs a down migration.

  It expects a repository, the migration version and the migration code.

  ## Examples

    migrate_down(Repo, 20080906120000, "DROP TABLE users")

  """
  defcallback migrate_down(Ecto.Repo.t, integer, binary) :: :ok | :missing_up | no_return

  @doc """
  Returns all migrated versions as integers.
  """
  defcallback migrated_versions(Ecto.Repo.t) :: [integer] | no_return
end
