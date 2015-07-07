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

  defmacro __using__(_) do
    quote do

      @behaviour Ecto.Adapters.Connection

      def after_connect(conn, opts) do
        repo = opts[:repo]
        if function_exported?(repo, :after_connect, 1) do
          try do
            Task.await(Task.async(fn -> repo.after_connect(conn) end))
          catch
            :exit, {:timeout, [Task, :await, [%Task{pid: task_pid}, _]]} ->
              Process.exit(task_pid, :kill)
              {:error, :timeout}
            :exit, {reason, {Task, :await, _}} ->
              {:error, reason}
            class, reason ->
              disconnect(conn)
              {class, reason, System.stacktrace()}
          else
            _ -> {:ok, conn}
          end
        else
          {:ok, conn}
        end
      end

      defoverridable [after_connect: 2]

    end
  end

  @doc """
  Connects to the underlying database.

  Should return a process which is linked to
  the caller process or an error.
  """
  defcallback connect(Keyword.t) :: {:ok, pid} | {:error, term}

  @doc """
  Called right after a connection has been opened and before it is returned
  to the pool.

  Should return a process which is linked to
  the caller process or an error.
  """
  defcallback after_connect(pid, Keywork.t) :: {:ok, pid} | {:error, term}

  @doc """
  Disconnects the given `pid`.

  If the given `pid` no longer exists, it should not raise.
  """
  defcallback disconnect(pid) :: :ok
end
