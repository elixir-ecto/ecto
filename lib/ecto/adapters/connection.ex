defmodule Ecto.Adapters.Connection do
  @moduledoc """
  Behaviour for connection processes.

  In order to use a connection, adapter developers need to implement
  two callbacks in a module, `connect/1` and `disconnect/1` defined
  in this module. The connection is started by passing the module that
  implements the callbacks and as well as the connection arguments.
  """

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
end
