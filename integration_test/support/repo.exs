defmodule Ecto.Integration.Repo do
  defmacro __using__(opts) do
    quote do
      use Ecto.Repo, unquote(opts)
      def log(cmd) do
        super(cmd)
        on_log = Process.delete(:on_log) || fn -> :ok end
        cond do
          is_function(on_log, 0) -> on_log.()
          is_function(on_log, 1) -> on_log.(cmd)
        end
      end
    end
  end
end
