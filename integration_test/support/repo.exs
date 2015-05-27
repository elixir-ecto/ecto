defmodule Ecto.Integration.Repo do
  defmacro __using__(opts) do
    quote do
      use Ecto.Repo, unquote(opts)
      def log(cmd) do
        super(cmd)
        on_log = Process.delete(:on_log) || fn -> :ok end
        on_log.()
      end
    end
  end
end
