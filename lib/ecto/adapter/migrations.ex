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
  Checks if a migration version has been run return
  """
  defcallback check_migration_version(Ecto.Repo.t, integer) :: :already_ran | no_return

  @doc """
  Inserts record of a migration version
  """
  defcallback insert_migration_version(Ecto.Repo.t, integer) :: :ok | no_return

  @doc """
  Removes record of migration version
  """
  defcallback delete_migration_version(Ecto.Repo.t, integer) :: :ok | no_return

  @doc """
  Executes migrations commands
  """
  defcallback execute_migration(Ecto.Repo.t, tuple) :: :ok | no_return
end
