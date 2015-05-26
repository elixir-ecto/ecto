defmodule Ecto.Integration.Repo do
  defmacro __using__(opts) do
    quote do
      use Ecto.Repo, unquote(opts)
        def log(cmd, fun) do
        before_log = Process.delete(:before_log) || fn -> :ok end
        before_log.()
        res = super(cmd, fun)
        after_log = Process.delete(:after_log) || fn -> :ok end
        after_log.()
        res
      end
    end
  end
end
