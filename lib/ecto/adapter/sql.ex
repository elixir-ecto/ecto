defmodule Ecto.Adapter.SQL do
  @moduledoc """
  Behaviour and implementation for SQL adapters.

  The implementation for SQL adapter provides a
  pooled based implementation of SQL and also expose
  a query function to developers.

  Developers that use `Ecto.Adapter.SQL` should implement
  the connection module with specifics on how to connect
  to the database and also how to translate the queries
  to SQL. See `Ecto.Adapter.SQL.Connection` for more info.
  """
end
