defmodule Ecto.Adapter.Migration  do
  @moduledoc """
  Specifies the adapter migrations API.
  """

  use Behaviour

  alias Ecto.Migration.Table
  alias Ecto.Migration.Index
  alias Ecto.Migration.Reference

  @typedoc "All migration commands"
  @type command ::
    raw :: String.t |
    {:create, Table.t, [table_subcommand]} |
    {:alter, Table.t, [table_subcommand]} |
    {:drop, Table.t} |
    {:create, Index.t} |
    {:drop, Index.t}

  @type table_subcommand ::
    {:add, field :: atom, type :: Ecto.Type.t | Reference.t, Keyword.t} |
    {:modify, field :: atom, type :: Ecto.Type.t | Reference.t, Keyword.t} |
    {:remove, field :: atom}

  @type ddl_object :: Table.t | Index.t

  @doc """
  Checks if the adapter supports ddl transaction.

  """
  defcallback supports_ddl_transaction? :: boolean

  @doc """
  Executes migration commands.

  ## Options

  * `:timeout` - The time in milliseconds to wait for the call to finish,
    `:infinity` will wait indefinitely (default: 5000);
  * `:log` - When false, does not log begin/commit/rollback queries
  """
  defcallback execute_ddl(Ecto.Repo.t, command, Keyword.t) :: :ok | no_return

  @doc """
  Checks if ddl value, like a table or index, exists.

  ## Options

  * `:timeout` - The time in milliseconds to wait for the call to finish,
    `:infinity` will wait indefinitely (default: 5000);
  * `:log` - When false, does not log begin/commit/rollback queries
  """
  defcallback ddl_exists?(Ecto.Repo.t, ddl_object, Keyword.t) :: boolean
end
