defmodule Ecto.Migration.Index do
  defstruct table: nil, name: nil, columns: [], unique: false

  def format_name(%__MODULE__{name: nil}=index) do
    [index.table, index.columns, "index"]
    |> List.flatten
    |> Enum.join("_")
  end

  def format_name(index), do: index.name
end
