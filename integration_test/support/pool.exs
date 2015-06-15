defmodule Ecto.Integration.Pool do
  alias Ecto.Integration.Connection
  alias Ecto.Adapters.Pool.Transaction

  defmacro __using__(pool_mod) do
    quote do
      def start_link(opts) do
        unquote(pool_mod).start_link(Connection, [size: 1] ++ opts)
      end

      def transaction(pool, timeout, fun) do
        Transaction.transaction(unquote(pool_mod), pool, timeout, fun)
      end
      defdelegate stop(pool), to: unquote(pool_mod)

      defoverridable [start_link: 1, stop: 1]
    end
  end
end
