defmodule Ecto.Migration.Dsl do
  defrecord Column, name: nil, type: nil

  defrecord CreateTable, name: nil, columns: [] do
    def column(name, type, table) do
      col = Column.new(name: name, type: type)
      table.columns(table.columns ++ [col])
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
