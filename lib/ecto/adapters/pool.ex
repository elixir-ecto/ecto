defmodule Ecto.Adapters.Pool do
  @modueldoc"""
  Behaviour for starting and stopping a pool of connections.
  """

  use Behaviour

  @type t :: atom | pid

  @doc """
  Start a pool of connections.

  `module` is the connection module, which should define the
  `Ecto.Adapters.Connection` callbacks, and `opts` are its (and the pool's)
  options.

  A pool should support the following options:

    * `:name` - The name of the pool
    * `:size` - The number of connections to keep in the pool

  Returns `{:ok, pid}` on starting the pool.

  Returns `{:error, reason}` if the pool could not be started. If the `reason`
  is  {:already_started, pid}}` a pool with the same name has already been
  started.
  """
  defcallback start_link(module, opts) ::
    {:ok, pid} | {:error, any} when opts: Keyword.t

  @doc """
  Stop a pool.
  """
  defcallback stop(t) :: :ok
end
