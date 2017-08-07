defmodule Ecto.Adapters.SQL.Connection do
  @moduledoc """
  Specifies the behaviour to be implemented by all SQL connections.
  """

  @typedoc "The prepared query which is an SQL command"
  @type prepared :: String.t

  @typedoc "The cache query which is a DBConnection Query"
  @type cached :: map

  @doc """
  Receives options and returns `DBConnection` supervisor child
  specification.
  """
  @callback child_spec(options :: Keyword.t) :: {module, Keyword.t}

  @doc """
  Prepares and executes the given query with `DBConnection`.
  """
  @callback prepare_execute(connection :: DBConnection.t, name :: String.t, prepared, params :: [term], options :: Keyword.t) ::
            {:ok, query :: map, term} | {:error, Exception.t}

  @doc """
  Executes the given prepared query with `DBConnection`.
  """
  @callback execute(connection :: DBConnection.t, prepared_query :: prepared, params :: [term], options :: Keyword.t) ::
            {:ok, term} | {:error, Exception.t}
  @callback execute(connection :: DBConnection.t, prepared_query :: cached, params :: [term], options :: Keyword.t) ::
            {:ok, term} | {:error | :reset, Exception.t}

  @doc """
  Returns a stream that prepares and executes the given query with
  `DBConnection`.
  """
  @callback stream(connection :: DBConnection.conn, prepared_query :: prepared, params :: [term], options :: Keyword.t) ::
            Enum.t

  @doc """
  Receives the exception returned by `query/4`.

  The constraints are in the keyword list and must return the
  constraint type, like `:unique`, and the constraint name as
  a string, for example:

      [unique: "posts_title_index"]

  Must return an empty list if the error does not come
  from any constraint.
  """
  @callback to_constraints(exception :: Exception.t) :: Keyword.t

  ## Queries

  @doc """
  Receives a query and must return a SELECT query.
  """
  @callback all(query :: Ecto.Query.t) :: iodata

  @doc """
  Receives a query and values to update and must return an UPDATE query.
  """
  @callback update_all(query :: Ecto.Query.t) :: iodata

  @doc """
  Receives a query and must return a DELETE query.
  """
  @callback delete_all(query :: Ecto.Query.t) :: iodata

  @doc """
  Returns an INSERT for the given `rows` in `table` returning
  the given `returning`.
  """
  @callback insert(prefix ::String.t, table :: String.t,
                   header :: [atom], rows :: [[atom | nil]],
                   on_conflict :: Ecto.Adapter.on_conflict, returning :: [atom]) :: iodata

  @doc """
  Returns an UPDATE for the given `fields` in `table` filtered by
  `filters` returning the given `returning`.
  """
  @callback update(prefix :: String.t, table :: String.t, fields :: [atom],
                   filters :: [atom], returning :: [atom]) :: iodata

  @doc """
  Returns a DELETE for the `filters` returning the given `returning`.
  """
  @callback delete(prefix :: String.t, table :: String.t,
                   filters :: [atom], returning :: [atom]) :: iodata

  ## DDL

  @doc """
  Receives a DDL command and returns a query that executes it.
  """
  @callback execute_ddl(command :: Ecto.Adapter.Migration.command) :: String.t | [iodata]
end
