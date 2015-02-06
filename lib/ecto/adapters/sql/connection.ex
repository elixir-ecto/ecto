defmodule Ecto.Adapters.SQL.Connection do
  use Behaviour

  @doc """
  Connects to the underlying database.

  Should return a process which is linked to
  the caller process or an error.
  """
  defcallback connect(Keyword.t) :: {:ok, pid} | {:error, term}

  @doc """
  Disconnects the given `pid`.

  If the given `pid` no longer exists, it should not raise.
  """
  defcallback disconnect(pid) :: :ok

  @doc """
  Executes the given query with params in connection.

  In case of success, it must return an `:ok` tuple containing
  a map with at least two keys:

    * `:num_rows` - the number of rows affected

    * `:rows` - the result set as a list. `nil` may be returned
      instead of the list if the command does not yield any row
      as result (but still yields the number of affected rows,
      like a `delete` command without returning would)
  """
  defcallback query(pid, query :: binary, params :: [term], opts :: Keyword.t) ::
              {:ok, %{rows: nil | [tuple], num_rows: non_neg_integer}} | {:error, Exception.t}

  ## Queries

  @doc """
  Receives a query and must return a SELECT query.
  """
  defcallback all(Ecto.Query.t) :: String.t

  @doc """
  Receives a query and values to update and must return an UPDATE query.
  """
  defcallback update_all(Ecto.Query.t, values :: Keyword.t) :: String.t

  @doc """
  Receives a query and must return a DELETE query.
  """
  defcallback delete_all(Ecto.Query.t) :: String.t

  @doc """
  Returns an INSERT for the given `fields` in `table` returning
  the given `returning`.
  """
  defcallback insert(table :: String.t, fields :: Keyword.t, returning :: [atom]) :: String.t

  @doc """
  Returns an UPDATE for the given `fields` in `table` filtered by
  `filters` returning the given `returning`.
  """
  defcallback update(table :: String.t, filters :: Keyword.t,
                     fields :: Keyword.t, returning :: [atom]) :: String.t

  @doc """
  Returns a DELETE for the `filters` returning the given `returning`.
  """
  defcallback delete(table :: String.t, filters :: Keyword.t, returning :: [atom]) :: String.t

  ## DDL

  @doc """
  Receives a DDL object and returns a query that checks its existence.
  """
  defcallback ddl_exists(Ecto.Adapter.Migrations.ddl_object) :: String.t

  @doc """
  Receives a DDL command and returns a query that executes it.
  """
  defcallback execute_ddl(Ecto.Adapter.Migrations.command) :: String.t

  ## Transaction

  @doc """
  Command to begin transaction.
  """
  defcallback begin_transaction :: String.t

  @doc """
  Command to rollback transaction.
  """
  defcallback rollback :: String.t

  @doc """
  Command to commit transaction.
  """
  defcallback commit :: String.t

  @doc """
  Command to emit savepoint.
  """
  defcallback savepoint(savepoint :: String.t) :: String.t

  @doc """
  Command to rollback to savepoint.
  """
  defcallback rollback_to_savepoint(savepoint :: String.t) :: String.t
end