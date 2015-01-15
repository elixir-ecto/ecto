defmodule Ecto.Adapter.Migrations  do
  @moduledoc """
  Specifies the adapter migrations API.
  """

  use Behaviour

  @typedoc "All migration commands"
  @type command ::
    raw :: String.t |
    {:create, Ecto.Migration.Table.t, [table_subcommand]} |
    {:alter, Ecto.Migration.Table.t, [table_subcommand]} |
    {:drop, Ecto.Migration.Table.t} |
    {:create, Ecto.Migration.Index.t} |
    {:drop, Ecto.Migration.Index.t}

  @typedoc "Table subcommands"
  @type table_subcommand ::
    {:add, field :: atom, type :: Ecto.Type.t | Ecto.Migration.Reference.t, Keyword.t} |
    {:modify, field :: atom, type :: Ecto.Type.t | Ecto.Migration.Reference.t, Keyword.t} |
    {:remove, field :: atom}

  @doc """
  Executes migration commands.

  It is recommended for adapters to use timeout of infinity in such
  commands, as tasks like adding indexes and upgrading tables can
  take hours or even days.
  """
  defcallback execute_ddl(Ecto.Repo.t, command) :: :ok | no_return

  @doc """
  Checks if ddl value, like a table or index, exists.
  """
  defcallback ddl_exists?(Ecto.Repo.t, Ecto.Migration.Table.t | Ecto.Migration.Index.t) :: boolean
end
