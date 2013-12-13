defmodule Ecto.Migration.DslTest do
  use ExUnit.Case
  import Ecto.Migration.Dsl

  test "creating table" do
    command = create_table(:products, fn(_) -> nil end)

    assert command == Ecto.Migration.Dsl.CreateTable[name: :products]
  end

  test "dropping table" do
    command = drop_table(:products)

    assert command == Ecto.Migration.Dsl.DropTable[name: :products]
  end

  test "creating index" do
    command = create_index(:products, [:name], unique: true)

    assert command == Ecto.Migration.Dsl.CreateIndex[table_name: :products,
                                                     columns: [:name],
                                                     unique: true]
  end

  test "dropping index" do
    command = drop_index(:products, [:name])

    assert command == Ecto.Migration.Dsl.DropIndex[table_name: :products, columns: [:name]]
  end
end
