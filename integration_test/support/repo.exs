defmodule Ecto.Integration.Repo do
  defmacro __using__(opts) do
    quote do
      use Ecto.Repo, unquote(opts)

      def init(_, opts) do
        loggers = [Ecto.LogEntry, {Ecto.Integration.Repo, :log, [:on_log]}]
        {:ok, Keyword.put(opts, :loggers, loggers)}
      end
    end
  end

  def log(entry, key) do
    on_log = Process.delete(key) || fn _ -> :ok end
    on_log.(entry)
    entry
  end
end
