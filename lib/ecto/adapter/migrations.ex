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
  defcallback execute_migration(Ecto.Repo.t, tuple :: {:create, :table, Ecto.Migration.Table.t, [{:add,    atom, atom, Keyword.t}]} |
                                                      {:drop,   :table, Ecto.Migration.Table.t} |
                                                      {:alter,  :table, Ecto.Migration.Table.t, [{:add,    atom, atom, Keyword.t} |
                                                                                                 {:modify, atom, atom, Keyword.t} |
                                                                                                 {:remove, atom} |
                                                                                                 {:rename, atom, atom}]} |
                                                      {:create, :index, Ecto.Migration.Index.t} |
                                                      {:drop,   :index, Ecto.Migration.Index.t}) :: :ok | no_return

  @doc """
  Returns all migrated versions as integers.
  """
  defcallback migrated_versions(Ecto.Repo.t) :: [integer] | no_return

  @doc """
  Checks if a column, table or index exists.
  """
  defcallback object_exists?(Ecto.Repo.t, tuple :: {:table, atom} | {:index, atom} | {:column, {atom, atom}}) :: boolean
end
