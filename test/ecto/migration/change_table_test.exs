defmodule Ecto.Migration.ChangeTableTest do
  use ExUnit.Case
  import Ecto.Migration.Dsl.ChangeTable

  test "adding column" do
    table = new.column(:name, :string)
    [{type, column}] = table.changes

    assert type == :add
    assert column.name == :name
    assert column.type == :string
  end

  test "removing column" do
    table = new.remove(:name)
    [{type, column}] = table.changes

    assert type == :remove
    assert column.name == :name
  end

  test "changing column" do
    table = new.change(:name, :string)
    [{type, column}] = table.changes

    assert type == :change
    assert column.name == :name
    assert column.type == :string
  end
end
