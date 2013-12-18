defmodule Ecto.Migration do
  alias Ecto.Migration.Runner

  defmacro __using__(_) do
    quote location: :keep do
      import Ecto.Migration.DSL
      def __migration__, do: true

      def up(repo, fun) do
        repo.transaction fn ->
          attempt(:forward, :up) || attempt(:forward, :change) ||
            raise Ecto.MigrationError.new(message: "#{__MODULE__} does not implement a `up/0` or `change/0` function")

          fun.()
        end
      end

      def down(repo, fun) do
        repo.transaction fn ->
          attempt(:forward, :down) || attempt(:reverse, :change) ||
            raise Ecto.MigrationError.new(message: "#{__MODULE__} does not implement a `down/0` or `change/0` function")

          fun.()
        end
      end

      defp attempt(direction, operation) do
        if function_exported?(__MODULE__, operation, 0) do
          Runner.direction(direction)
          apply(__MODULE__, operation, [])
          :ok
        end
      end
    end
  end

  defrecord Table, name: nil, key: true

  defrecord Index, table: nil, name: nil, columns: [], unique: false do
    def format_name(Index[name: nil]=index) do
      [index.table, index.columns, "index"]
      |> List.flatten
      |> Enum.join("_")
    end

    def format_name(index), do: index.name
  end
end
