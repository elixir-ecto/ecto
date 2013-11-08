defmodule Ecto.Adapter.Migrations  do
  @moduledoc """
  Specifies the migrations API that an adapter is required to implement.
  """

  use Behaviour

  @doc """
  Runs an up migration on the given repo, the migration is identified by the
  supplied version.

  ## Examples

    MyRepo.migrate_up(Repo, 20080906120000, "CREATE TABLE users(id serial, name text)")

  """
  defcallback migrate_up(Ecto.Repo.t, integer, binary) :: :ok | :already_up | no_return

  @doc """
  Runs a down migration on the given repo, the migration is identified by the
  supplied version.

  ## Examples

    MyRepo.migrate_down(Repo, 20080906120000, "DROP TABLE users")

  """
  defcallback migrate_down(Ecto.Repo.t, integer, binary) :: :ok | :missing_up | no_return

  @doc """
  Returns the versions of all migrations that have been run on the given repo.
  """
  defcallback migrated_versions(Ecto.Repo.t) :: [integer] | no_return
end
