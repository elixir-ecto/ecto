defmodule Ecto.MigratorDslTest do
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
end
