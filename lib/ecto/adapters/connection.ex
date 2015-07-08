defmodule Ecto.Adapters.Connection do
  @moduledoc """
  Behaviour for adapters that rely on connections.

  In order to use a connection, adapter developers need to implement
  a single callback in a module: `connect/1` defined in this module.

  The benefits of implementing this module is that the adapter can
  then be used with all the different pools provided by Ecto.
  """

  use Behaviour

  @doc """
  Connects to the underlying database.

  Should return a process which is linked to
  the caller process or an error.
  """
  defcallback connect(Keyword.t) :: {:ok, pid} | {:error, term}

  @doc """
  Executes the connect in the given module, ensuring the repository's
  `after_connect/1` is invoked in the process.
  """
  def connect(module, opts) do
    case module.connect(opts) do
      {:ok, conn} ->
        after_connect(conn, opts)
      {:error, _} = error ->
        error
    end
  end

  defp after_connect(conn, opts) do
    repo = opts[:repo]
    if function_exported?(repo, :after_connect, 1) do
      try do
        Task.async(fn -> repo.after_connect(conn) end)
        |> Task.await(opts[:timeout])
      catch
        :exit, {:timeout, [Task, :await, [%Task{pid: task_pid}, _]]} ->
          shutdown(task_pid, :brutal_kill)
          shutdown(conn, :brutal_kill)
          {:error, :timeout}
        :exit, {reason, {Task, :await, _}} ->
          shutdown(conn, :brutal_kill)
          {:error, reason}
      else
        _ -> {:ok, conn}
      end
    else
      {:ok, conn}
    end
  end

  @doc """
  Shutdown the given connection `pid`.

  If `pid` does not exit within `timeout` it is killed, or it is killed
  immediately if `:brutal_kill`.
  """
  @spec shutdown(pid, timeout | :brutal_kill) :: :ok
  def shutdown(pid, shutdown \\ 5_000)

  def shutdown(pid, :brutal_kill) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    receive do
      {:DOWN, ^ref, _, _, _} -> :ok
    end
  end

  def shutdown(pid, timeout) do
    ref = Process.monitor(pid)
    Process.exit(pid, :shutdown)
    receive do
      {:DOWN, ^ref, _, _, _} -> :ok
    after
      timeout ->
        Process.exit(pid, :kill)
        receive do
          {:DOWN, ^ref, _, _, _} -> :ok
        end
    end
  end
end
