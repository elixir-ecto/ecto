defmodule Ecto.Migration.DslTest do
  use ExUnit.Case
  import Ecto.Migration.Dsl

  test "creating table" do
    command = create_table(:products)

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

  test "change table" do
    command = change_table(:products)

    assert command == Ecto.Migration.Dsl.ChangeTable[name: :products]
  end

  test "adding column" do
    command = add_column(:products, :summary, :string, limit: 20)

    assert command == Ecto.Migration.Dsl.ChangeTable[name: :products,
                                                     changes: [{:add, Ecto.Migration.Dsl.Column[name: :summary,
                                                                                                type: :string,
                                                                                                limit: 20]}]]
  end

  test "remove column" do
    command = remove_column(:products, :summary)

    assert command == Ecto.Migration.Dsl.ChangeTable[name: :products,
                                                     changes: [{:remove, Ecto.Migration.Dsl.Column[name: :summary]}]]
  end
end
