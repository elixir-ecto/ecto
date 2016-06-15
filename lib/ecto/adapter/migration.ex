defmodule Ecto.Adapter.Migration  do
  @moduledoc """
  Specifies the adapter migrations API.
  """

  alias Ecto.Migration.Table
  alias Ecto.Migration.Index
  alias Ecto.Migration.Reference

  @typedoc "All migration commands"
  @type command ::
    raw :: String.t |
    {:create, Table.t, [table_subcommand]} |
    {:create_if_not_exists, Table.t, [table_subcommand]} |
    {:alter, Table.t, [table_subcommand]} |
    {:drop, Table.t} |
    {:drop_if_exists, Table.t} |
    {:create, Index.t} |
    {:create_if_not_exists, Index.t} |
    {:drop, Index.t} |
    {:drop_if_exists, Index.t}

  @typedoc "All commands allowed within the block passed to `table/2`"
  @type table_subcommand ::
    {:add, field :: atom, type :: Ecto.Type.t | Reference.t, Keyword.t} |
    {:modify, field :: atom, type :: Ecto.Type.t | Reference.t, Keyword.t} |
    {:remove, field :: atom}

  @typedoc """
  A DDL object is a struct that represents a table or index in a database schema.
  These database objects can be modified through the use of a Data Definition Language,
  hence the name DDL object.
  """
  @type ddl_object :: Table.t | Index.t

  @doc """
  Checks if the adapter supports ddl transaction.
  """
  @callback supports_ddl_transaction? :: boolean

  @doc """
  Executes migration commands.

  ## Options

    * `:timeout` - The time in milliseconds to wait for the query call to
      finish, `:infinity` will wait indefinitely (default: 15000);
    * `:pool_timeout` - The time in milliseconds to wait for calls to the pool
      to finish, `:infinity` will wait indefinitely (default: 5000);
    * `:log` - When false, does not log begin/commit/rollback queries
  """
  @callback execute_ddl(repo :: Ecto.Repo.t, command, options :: Keyword.t) :: :ok | no_return
end
