defmodule Ecto.Migration.Dsl do
  defrecord CreateTable, name: nil
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
