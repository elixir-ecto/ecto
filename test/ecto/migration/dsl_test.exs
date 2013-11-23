defmodule Ecto.MigratorDslTest do
  use ExUnit.Case
  import Ecto.Migration.Dsl

  test "creating table" do
    ast = tables.create(:products, fn(_) -> nil end)

    assert ast == Ecto.Migration.Dsl.CreateTable[name: :products]
  end

  test "dropping table" do
    ast = tables.drop(:products)

    assert ast == Ecto.Migration.Dsl.DropTable[name: :products]
  end
end
