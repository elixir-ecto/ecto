defmodule Ecto.Adapters.SQL.Connection do
  @moduledoc """
  Specifies the behaviour to be implemented by all SQL connections.
  """

  @doc """
  Receives options and returns `DBConnection` module and
  options to use to handle queries.
  """
  @callback connection(Keyword.t) :: {module, Keyword.t}

  @doc """
  Sends the given query to `DBConnection`.
  """
  @callback query(DBConnection.t, sql :: String.t, params :: [term], Keyword.t) ::
            {:ok, term} | {:error, Exception.t}

  @doc """
  Prepares and executes the given query with `DBConnection`.
  """
  @callback prepare_execute(DBConnection.t, sql :: String.t, params :: [term], Keyword.t) ::
            {:ok, query :: map, term} | {:error, Exception.t}

  @doc """
  Executes the given prepared query with `DBConnection`.
  """
  @callback execute(DBConnection.t, query :: map, params :: [term], Keyword.t) ::
            {:ok, term} | {:error, Exception.t}

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
  Returns an INSERT for the given `rows` in `table` returning
  the given `returning`.
  """
  @callback insert(prefix ::String.t, table :: String.t,
                   header :: [atom], rows :: [[atom | nil]], returning :: [atom]) :: String.t

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
end
