defmodule Ecto.Integration.Repo do
  defmacro __using__(opts) do
    quote do
      config = Application.get_env(:ecto, __MODULE__)
      config = Keyword.put(config, :loggers, [Ecto.LogEntry,
                                              {Ecto.Integration.Repo, :log, [:on_log]}])
      Application.put_env(:ecto, __MODULE__, config)
      use Ecto.Repo, unquote(opts)
    end
  end

  def log(entry, key) do
    on_log = Process.delete(key) || fn _ -> :ok end
    on_log.(entry)
    entry
  end
end
