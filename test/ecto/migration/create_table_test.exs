defmodule Ecto.Migration.CreateTableTest do
  use ExUnit.Case
  import Ecto.Migration.Dsl.CreateTable

  test "adding columns" do
    table = new.column(:name, :string)
    column = List.last(table.columns)

    assert Enum.count(table.columns) == 1
    assert column.name == :name
    assert column.type == :string
  end

  test "adding string column" do
    table = new.string(:name)
    column = List.last(table.columns)

    assert column.name == :name
    assert column.type == :string
  end

  test "adding integer column" do
    table = new.integer(:num)
    column = List.last(table.columns)

    assert column.name == :num
    assert column.type == :integer
  end

  test "adding float column" do
    table = new.float(:num)
    column = List.last(table.columns)

    assert column.name == :num
    assert column.type == :float
  end

  test "adding boolean column" do
    table = new.boolean(:flag)
    column = List.last(table.columns)

    assert column.name == :flag
    assert column.type == :boolean
  end

  test "adding binary column" do
    table = new.binary(:flag)
    column = List.last(table.columns)

    assert column.name == :flag
    assert column.type == :binary
  end

  test "adding list column" do
    table = new.list(:flag)
    column = List.last(table.columns)

    assert column.name == :flag
    assert column.type == :list
  end

  test "adding datetime column" do
    table = new.datetime(:flag)
    column = List.last(table.columns)

    assert column.name == :flag
    assert column.type == :datetime
  end

  test "adding timestamps" do
    table = new.timestamps
    [created_at, updated_at] = table.columns

    assert created_at.name == :created_at
    assert created_at.type == :datetime

    assert updated_at.name == :updated_at
    assert updated_at.type == :datetime
  end
end
