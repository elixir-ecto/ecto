defmodule Ecto.Integration.Repo do
  defmacro __using__(opts) do
    quote do
      loggers = [loggers: [Ecto.LogEntry, {Ecto.Integration.Repo, :log, [:on_log]}]]
      use Ecto.Repo, loggers ++ unquote(opts)
    end
  end

  def log(entry, key) do
    on_log = Process.delete(key) || fn _ -> :ok end
    on_log.(entry)
    entry
  end
end
