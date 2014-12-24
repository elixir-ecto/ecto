defmodule Ecto.Adapter.Migrations  do
  @moduledoc """
  Specifies the adapter migrations API.
  """

  use Behaviour

  @doc """
  Records that a migration has completed successfully.

  ## Examples

    insert_migration_version(Repo, 20080906120000)

  """
  defcallback insert_migration_version(Ecto.Repo.t, integer) :: :ok | no_return

  @doc """
  Removes record of migration when version is rolled back.

  ## Examples

    delete_migration_version(Repo, 20080906120000)

  """
  defcallback delete_migration_version(Ecto.Repo.t, integer) :: :ok | no_return

  @doc """
  Executes migration commands like `{:create, ..}`, `{:drop, ..}`.

  ## Examples

    execute_migration(Repo, {:drop, :index, %Index{name: "products$test"}})

  """
  defcallback execute_migration(Ecto.Repo.t, tuple) :: :ok | no_return

  @doc """
  Returns all migrated versions as integers.
  """
  defcallback migrated_versions(Ecto.Repo.t) :: [integer] | no_return

  @doc """
  Checks if an object exists.
  """
  defcallback object_exists?(Ecto.Repo.t, tuple) :: boolean
end
