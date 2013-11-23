defmodule Ecto.Migration.Dsl do
  defrecord Column, name: nil, type: nil

  defrecord CreateTable, name: nil, columns: [] do
    def column(name, type, table) do
      col = Column.new(name: name, type: type)
      table.columns(table.columns ++ [col])
    end

    def string(name, table),   do: column(name, :string, table)
    def integer(name, table),  do: column(name, :integer, table)
    def float(name, table),    do: column(name, :float, table)
    def boolean(name, table),  do: column(name, :boolean, table)
    def binary(name, table),   do: column(name, :binary, table)
    def list(name, table),     do: column(name, :list, table)
    def datetime(name, table), do: column(name, :datetime, table)
  end

  defrecord DropTable, name: nil

  def drop_table(name) do
    DropTable.new(name: name)
  end

  def create_table(name, fun) do
    table = CreateTable.new(name: name)
    fun.(table)
    table
  end
end
