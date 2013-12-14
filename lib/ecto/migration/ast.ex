defmodule Ecto.Migration.Ast do
  defrecord Column, name: nil, type: nil, null: nil, limit: nil, default: :undefined

  defrecord CreateTable, name: nil, columns: [] do
    use Ecto.Migration.Dsl.ColumnAliases

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
    use Ecto.Migration.Dsl.ColumnAliases

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
end
