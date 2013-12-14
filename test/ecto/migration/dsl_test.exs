defmodule Ecto.Migration.DslTest do
  use ExUnit.Case

  alias Ecto.Migration.Ast.CreateTable
  alias Ecto.Migration.Ast.ChangeTable
  alias Ecto.Migration.Ast.DropTable
  alias Ecto.Migration.Ast.CreateIndex
  alias Ecto.Migration.Ast.DropIndex
  alias Ecto.Migration.Ast.Column

  import Ecto.Migration.Dsl

  test "creating table" do
    command = create_table(:products)

    assert command == CreateTable[name: :products]
  end

  test "dropping table" do
    command = drop_table(:products)

    assert command == DropTable[name: :products]
  end

  test "creating index" do
    command = create_index(:products, [:name], unique: true)

    assert command == CreateIndex[table_name: :products, columns: [:name], unique: true]
  end

  test "dropping index" do
    command = drop_index(:products, [:name])

    assert command == DropIndex[table_name: :products, columns: [:name]]
  end

  test "change table" do
    command = change_table(:products)

    assert command == ChangeTable[name: :products]
  end

  test "adding column" do
    command = add_column(:products, :summary, :string, limit: 20)

    assert command == ChangeTable[name: :products, changes: [
        {:add, Column[name: :summary, type: :string, limit: 20]}]]
  end

  test "remove column" do
    command = remove_column(:products, :summary)

    assert command == ChangeTable[name: :products, changes: [
        {:remove, Column[name: :summary]}]]
  end

  test "changing column" do
    command = change_column(:products, :summary, :string, limit: 20)

    assert command == ChangeTable[name: :products, changes: [
        {:change, Column[name: :summary, type: :string, limit: 20]}]]
  end
end
