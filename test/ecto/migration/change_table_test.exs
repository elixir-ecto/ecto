defmodule Ecto.Migration.ChangeTableTest do
  use ExUnit.Case
  import Ecto.Migration.Dsl.ChangeTable

  test "adding column" do
    table = new.column(:name, :string)
    [{type, column}] = table.columns

    assert type == :add
    assert column.name == :name
    assert column.type == :string
  end
end
