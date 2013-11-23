defmodule Ecto.Migration.CreateTableTest do
  use ExUnit.Case

  test "adds columns" do
    table = Ecto.Migration.Dsl.CreateTable.new
                                          .column(:name, :string)
    column = List.last(table.columns)

    assert Enum.count(table.columns) == 1
    assert column.name == :name
    assert column.type == :string
  end
end
