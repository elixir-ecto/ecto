defmodule Ecto.Migration.Dsl do
  defmodule ColumnAliases do
    defmacro __using__(_module) do
      quote do
        def string(name, table),      do: table.column(name, :string)
        def integer(name, table),     do: table.column(name, :integer)
        def float(name, table),       do: table.column(name, :float)
        def boolean(name, table),     do: table.column(name, :boolean)
        def binary(name, table),      do: table.column(name, :binary)
        def list(name, table),        do: table.column(name, :list)
        def datetime(name, table),    do: table.column(name, :datetime)
        def primary_key(name, table), do: table.column(name, :primary_key)

        def timestamps(table) do
          table.datetime(:created_at)
               .datetime(:updated_at)
        end
      end
    end
  end

  alias Ecto.Migration.Ast.CreateTable
  alias Ecto.Migration.Ast.ChangeTable
  alias Ecto.Migration.Ast.DropTable
  alias Ecto.Migration.Ast.CreateIndex
  alias Ecto.Migration.Ast.DropIndex

  def drop_table(name) do
    DropTable.new(name: name)
  end

  def create_table(name) do
    CreateTable.new(name: name)
  end

  def change_table(name) do
    ChangeTable.new(name: name)
  end

  def create_index(table_name, columns, [unique: unique] // [unique: false]) do
    CreateIndex.new(table_name: table_name, columns: columns, unique: unique)
  end

  def drop_index(table_name, columns) do
    DropIndex.new(table_name: table_name, columns: columns)
  end

  def add_column(table_name, name, type, options // []) do
    change_table(table_name).column(name, type, options)
  end

  def remove_column(table_name, name) do
    change_table(table_name).remove(name)
  end

  def change_column(table_name, name, type, options // []) do
    change_table(table_name).change(name, type, options)
  end
end
