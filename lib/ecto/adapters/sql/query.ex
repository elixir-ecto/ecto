defmodule Ecto.Adapters.SQL.Query do
  @moduledoc """
  Specifies the behaviour to be implemented by the
  connection for handling all SQL queries.
  """

  @type result :: {:ok, %{rows: nil | [tuple], num_rows: non_neg_integer}} |
                  {:error, Exception.t}

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
  @callback query(pid, query :: binary, params :: list(), opts :: Keyword.t) :: result

  @doc """
  Receives the exception returned by `query/4`.

  The constraints are in the keyword list and must return the
  constraint type, like `:unique`, and the constraint name as
  a string, for example:

      [unique: "posts_title_index"]

  Must return an empty list if the error does not come
  from any constraint.
  """
  @callback to_constraints(Exception.t) :: Keyword.t

  @doc """
  Decodes the given result set given the mapper function.
  """
  @callback decode(result, mapper :: (term -> term)) :: result

  ## Queries

  @doc """
  Receives a query and must return a SELECT query.
  """
  @callback all(Ecto.Query.t) :: String.t

  @doc """
  Receives a query and values to update and must return an UPDATE query.
  """
  @callback update_all(Ecto.Query.t) :: String.t

  @doc """
  Receives a query and must return a DELETE query.
  """
  @callback delete_all(Ecto.Query.t) :: String.t

  @doc """
  Returns an INSERT for the given `fields` in `table` returning
  the given `returning`.
  """
  @callback insert(prefix ::String.t, table :: String.t,
                     fields :: [atom], returning :: [atom]) :: String.t

  @doc """
  Returns an UPDATE for the given `fields` in `table` filtered by
  `filters` returning the given `returning`.
  """
  @callback update(prefix :: String.t, table :: String.t, fields :: [atom],
                     filters :: [atom], returning :: [atom]) :: String.t

  @doc """
  Returns a DELETE for the `filters` returning the given `returning`.
  """
  @callback delete(prefix :: String.t, table :: String.t,
                     filters :: [atom], returning :: [atom]) :: String.t

  ## DDL

  @doc """
  Receives a DDL command and returns a query that executes it.
  """
  @callback execute_ddl(Ecto.Adapter.Migration.command) :: String.t

  ## Transaction

  @doc """
  Command to begin transaction.
  """
  @callback begin_transaction :: String.t

  @doc """
  Command to rollback transaction.
  """
  @callback rollback :: String.t

  @doc """
  Command to commit transaction.
  """
  @callback commit :: String.t

  @doc """
  Command to emit savepoint.
  """
  @callback savepoint(savepoint :: String.t) :: String.t

  @doc """
  Command to rollback to savepoint.
  """
  @callback rollback_to_savepoint(savepoint :: String.t) :: String.t
end
