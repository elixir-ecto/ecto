defmodule Ecto.Adapter.Migrations  do
  @moduledoc """
  Specifies the migrations API that an adapter is required to implement.
  """

  use Behaviour

  @doc """
  Returns the versions of all migrations that have been run on the given repo.
  """
  defcallback migrated_versions(Ecto.Repo.t) :: [integer] | no_return

  @doc """
  Records that a migration has completed successfully.
  """
  defcallback insert_migration_version(Ecto.Repo.t, integer) :: :ok | no_return

  @doc """
  Removes record of migration when version is rolled back.
  """
  defcallback delete_migration_version(Ecto.Repo.t, integer) :: :ok | no_return

  @doc """
  Executes migration commands like `{:create, ..}`, `{:drop, ..}`.
  """
  defcallback execute_migration(Ecto.Repo.t, tuple) :: :ok | no_return
end
