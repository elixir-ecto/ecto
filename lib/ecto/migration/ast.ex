defmodule Ecto.Migration.Ast do

  defrecord Table, name: nil, key: true

  defrecord Index, table: nil, name: nil, columns: [], unique: false do
    def actual_name(index) do
      case index.name do
        nil -> [index.table, index.columns, "index"]
                 |> List.flatten
                 |> Enum.join("_")
        _ -> index.name
      end
    end
  end
end
