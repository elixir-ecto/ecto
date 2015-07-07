defmodule Ecto.Adapters.Connection do
  @moduledoc """
  Behaviour for adapters that rely on connections.

  In order to use a connection, adapter developers need to implement
  two callbacks in a module, `connect/1` and `disconnect/1` defined
  in this module.

  For example, Ecto pools rely on the functions defined in the module
  in order to provide pooling.
  """

  use Behaviour

  def after_connect(mod, conn, opts) do
    repo = opts[:repo]
    if function_exported?(repo, :after_connect, 1) do
      try do
        Task.async(fn -> repo.after_connect(conn) end)
        |> Task.await(opts[:timeout])
      catch
        :exit, {:timeout, [Task, :await, [%Task{pid: task_pid}, _]]} ->
          Process.exit(task_pid, :kill)
          {:error, :timeout}
        :exit, {reason, {Task, :await, _}} ->
          mod.disconnect(conn)
          {:error, reason}
      else
        _ -> {:ok, conn}
      end
    else
      {:ok, conn}
    end
  end

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
