defmodule Ecto.Migration do
  alias Ecto.Migration.Runner

  defmacro __using__(_) do
    quote location: :keep do
      import Ecto.Migration.Dsl
      def __migration__, do: true

      def up(repo, fun) do
        Runner.direction(:up)

        repo.transaction fn ->
          if function_exported?(__MODULE__, :up, 0) do
            __MODULE__.up
          else
            __MODULE__.change
          end

          fun.()
        end
      end

      def down(repo, fun) do
        repo.transaction fn ->
          if function_exported?(__MODULE__, :down, 0) do
            Runner.direction(:up)
            __MODULE__.down
          else
            Runner.direction(:down)
            __MODULE__.change
          end

          fun.()
        end
      end
    end
  end

  defrecord Table, name: nil, key: true

  defrecord Index, table: nil, name: nil, columns: [], unique: false do
    def format_name(index) do
      case index.name do
        nil -> [index.table, index.columns, "index"]
               |> List.flatten
               |> Enum.join("_")
        _   -> index.name
      end
    end
  end
end
