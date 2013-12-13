defmodule Ecto.Migration.Dsl do
  defrecord Column, name: nil, type: nil, null: nil, limit: nil, default: :undefined

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

  defrecord CreateTable, name: nil, columns: [] do
    use ColumnAliases

    def build(options // [key: true]) do
      new.setup_key(options[:key])
    end

    def column(name, type, options // [], table) do
      col = Column.new(Dict.merge(options, name: name, type: type))
      table.columns(table.columns ++ [col])
    end

    def setup_key(true, table), do: table.primary_key(:id)
    def setup_key(_, table),    do: table
  end

  defrecord ChangeTable, name: nil, changes: [] do
    use ColumnAliases

    def column(name, type, options // [], table) do
      col = Column.new(Dict.merge(options, name: name, type: type))
      table.changes(table.changes ++ [{:add, col}])
    end

    def remove(name, table) do
      col = Column.new(name: name)
      table.changes(table.changes ++ [{:remove, col}])
    end

    def change(name, type, options // [], table) do
      col = Column.new(Dict.merge(options, name: name, type: type))
      table.changes(table.changes ++ [{:change, col}])
    end
  end

  defrecord DropTable, name: nil

  defrecord CreateIndex, table_name: nil, unique: false, columns: []
  defrecord DropIndex, table_name: nil, columns: []

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
    change_table(table_name)
      .column(name, type, options)
  end
end
