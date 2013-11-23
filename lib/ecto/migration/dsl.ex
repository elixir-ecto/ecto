defmodule Ecto.Migration.Dsl do
  defrecord CreateTable, name: nil
  defrecord DropTable, name: nil

  defmodule Tables do
    def create(name, fun) do
      table = CreateTable.new(name: name)
      fun.(table)
      table
    end

    def drop(name) do
      DropTable.new(name: name)
    end
  end

  def tables do
    Tables
  end
end
