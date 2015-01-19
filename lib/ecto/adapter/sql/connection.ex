defmodule Ecto.Adapter.SQL.Connection do
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

  It must return an `:ok` tuple containing a tuple with the
  result set entries as a list and the number of entries being
  returned.

  `nil` may be returned instead of the list if the command does
  not yield any row as result (but still yields the number of
  affected rows, like a `delete` command would).
  """
  defcallback query(pid, query :: binary, params :: [term], opts :: Keyword.t) ::
              {:ok, {nil | [tuple], non_neg_integer}} | {:error, Exception.t}
end