defmodule Ecto.Integration.Repo do
  defmacro __using__(opts) do
    quote do
      use Ecto.Repo,
        [loggers: [{Ecto.LogEntry, :log, []},
                   {Ecto.Integration.Repo, :log, [:on_log]}]] ++ unquote(opts)
    end
  end

  def log(entry, key) do
    on_log = Process.delete(key) || fn _ -> :ok end
    on_log.(entry)
    entry
  end
end
