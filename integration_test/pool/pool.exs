defmodule Ecto.Integration.Pool do
  alias Ecto.Adapters.Pool

  defmodule Connection do
    @behaviour Ecto.Adapters.Connection
    def connect(_opts) do
      Agent.start_link(fn -> [] end)
    end

    def disconnect(conn) do
      Agent.stop(conn)
    end
  end

  defmacro __using__(pool_mod) do
    quote do
      def start_link(opts) do
        unquote(pool_mod).start_link(Connection, [size: 1] ++ opts)
      end

      def transaction(pool, timeout, fun) do
        Pool.transaction(unquote(pool_mod), pool, timeout, fun)
      end

      def run(pool, timeout, fun) do
        Pool.run(unquote(pool_mod), pool, timeout, fun)
      end

      defdelegate stop(pool), to: unquote(pool_mod)

      defoverridable [start_link: 1, stop: 1]
    end
  end
end
