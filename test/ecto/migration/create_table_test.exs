defmodule Ecto.Migration.CreateTableTest do
  use ExUnit.Case
  import Ecto.Migration.Dsl.CreateTable

  test "adding columns" do
    table = build.column(:name, :string)
    [_id, column] = table.columns

    assert column.name == :name
    assert column.type == :string
  end

  test "adding string column" do
    table = build.string(:name)
    [_id, column] = table.columns

    assert column.name == :name
    assert column.type == :string
  end

  test "adding integer column" do
    table = build.integer(:num)
    [_id, column] = table.columns

    assert column.name == :num
    assert column.type == :integer
  end

  test "adding float column" do
    table = build.float(:num)
    [_id, column] = table.columns

    assert column.name == :num
    assert column.type == :float
  end

  test "adding boolean column" do
    table = build.boolean(:flag)
    [_id, column] = table.columns

    assert column.name == :flag
    assert column.type == :boolean
  end

  test "adding binary column" do
    table = build.binary(:flag)
    [_id, column] = table.columns

    assert column.name == :flag
    assert column.type == :binary
  end

  test "adding list column" do
    table = build.list(:flag)
    [_id, column] = table.columns

    assert column.name == :flag
    assert column.type == :list
  end

  test "adding datetime column" do
    table = build.datetime(:flag)
    [_id, column] = table.columns

    assert column.name == :flag
    assert column.type == :datetime
  end

  test "adding timestamps" do
    table = build.timestamps
    [_id, created_at, updated_at] = table.columns

    assert created_at.name == :created_at
    assert created_at.type == :datetime

    assert updated_at.name == :updated_at
    assert updated_at.type == :datetime
  end

  test "adds primary key" do
    table = build
    [id] = table.columns

    assert id.name == :id
    assert id.type == :primary_key
  end

  test "can disable primary key" do
    table = build(key: false)
    assert [] == table.columns
  end
end
