defmodule Ecto.Migration.Dsl do
  defrecord Column, name: nil, type: nil

  defrecord CreateTable, name: nil, columns: [] do
    def column(name, type, table) do
      col = Column.new(name: name, type: type)
      table.columns(table.columns ++ [col])
    end

    def string(name, table),   do: table.column(name, :string)
    def integer(name, table),  do: table.column(name, :integer)
    def float(name, table),    do: table.column(name, :float)
    def boolean(name, table),  do: table.column(name, :boolean)
    def binary(name, table),   do: table.column(name, :binary)
    def list(name, table),     do: table.column(name, :list)
    def datetime(name, table), do: table.column(name, :datetime)

    def timestamps(table) do
      table.datetime(:created_at)
           .datetime(:updated_at)
    end
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
