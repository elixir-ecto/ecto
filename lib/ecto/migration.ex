defmodule Ecto.Migration do
  defmacro __using__(_) do
    quote location: :keep do
      import Ecto.Migration.Dsl
      def __migration__, do: true
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
