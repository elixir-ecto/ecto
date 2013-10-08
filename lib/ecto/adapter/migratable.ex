defmodule Ecto.Adapter.Migratable  do
  @moduledoc """
  This module specifies the migrations API that an adapter is required to
  implement.
  """

  use Behaviour

  @doc """
  Running a migration with a specific version.
  
  ## Examples

    MyRepo.migrate_up(Repo, 20080906120000, "CREATE TABLE users(id serial, name varchar(50));")
  
  """
  defcallback migrate_up(Ecto.Repo.t, integer, binary) :: :ok | :already_up | { :error, error :: term }

  @doc """
  Running a migration with a specific version.

  ## Examples

    MyRepo.migrate_down(Repo, 20080906120000, "DROP TABLE users;")
  
  """
  defcallback migrate_down(Ecto.Repo.t, integer, binary) :: :ok | :missing_up | { :error, error :: term } 

  @doc """
  Returns all versions migrated in the database.
  """
  defcallback migrated_versions(Ecto.Repo.t) :: [integer]

end