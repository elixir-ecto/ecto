defmodule Ecto.Adapter.Migrations  do
  @moduledoc """
  Specifies the adapter migrations API.
  """

  use Behaviour

  @typedoc "All migration commands"
  @type commands ::
    command :: String.t |
    {:create, Ecto.Migration.Table.t, [table_subcommands]} |
    {:alter, Ecto.Migration.Table.t, [table_subcommands]} |
    {:drop, Ecto.Migration.Table.t} |
    {:create, Ecto.Migration.Index.t} |
    {:drop, Ecto.Migration.Index.t}

  @typedoc "Table subcommands"
  @type table_subcommands ::
    {:add, field :: atom, type :: Ecto.Type.t | Ecto.Migration.Reference.t, Keyword.t} |
    {:modify, field :: atom, type :: Ecto.Type.t | Ecto.Migration.Reference.t, Keyword.t} |
    {:rename, from :: atom, to :: atom} |
    {:remove, field :: atom}

  # TODO: We can insert / delete migrations using the existing adapter API

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
  Returns all migrated versions as integers.
  """
  defcallback migrated_versions(Ecto.Repo.t) :: [integer] | no_return

  # TODO: Is there a better name for execute and exists?

  @doc """
  Executes migration commands like `{:create, ..}`, `{:drop, ..}`.

  ## Examples

    execute_migration(Repo, {:drop, %Ecto.Migration.Index{name: "products$test"}})

  """
  defcallback execute_migration(Ecto.Repo.t, commands) :: :ok | no_return

  @doc """
  Checks if a column, table or index exists.
  """
  defcallback object_exists?(Ecto.Repo.t, Ecto.Migration.Table.t | Ecto.Migration.Index.t) :: boolean
end
