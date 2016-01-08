defmodule Ecto.Integration.CheckConstraintTest do
  use ExUnit.Case, async: true

  alias Ecto.Integration.TestRepo
  import Ecto.Migrator, only: [up: 4, down: 4]

  defmodule CheckConstraintMigration do
    use Ecto.Migration

    @table table(:products)

    def change do
      create @table do
        add :price, :integer
      end
      create constraint(@table.name, "positive_price", check: "price > 0")
    end
  end

  defmodule CheckConstraintModel do
    use Ecto.Integration.Schema

    schema "products" do
      field :price, :integer
    end
  end

  test "creating, using, and dropping a check constraint" do
    assert :ok == up(TestRepo, 20120806000000, CheckConstraintMigration, log: false)

    # When the changeset doesn't expect the db error
    changeset = Ecto.Changeset.change(%CheckConstraintModel{}, price: -10)
    exception =
      assert_raise(Ecto.ConstraintError, ~r/constraint error when attempting to insert model/, fn ->
        TestRepo.insert(changeset)
      end
      )
    assert exception.message =~ "check: positive_price"
    assert exception.message =~ "The changeset has not defined any constraint."

    # When the changeset does expect the db error, but doesn't give a custom message
    changeset = Ecto.Changeset.change(%CheckConstraintModel{}, price: -10)
    {:error, changeset} =
      changeset
      |> Ecto.Changeset.check_constraint(:price, name: :positive_price)
      |> TestRepo.insert()
    assert changeset.errors == [price: "violates check 'positive_price'"]
    assert changeset.model.__meta__.state == :built

    # When the changeset does expect the db error and gives a custom message
    changeset = Ecto.Changeset.change(%CheckConstraintModel{}, price: -10)
    {:error, changeset} =
      changeset
      |> Ecto.Changeset.check_constraint(:price, name: :positive_price, message: "price must be greater than 0")
      |> TestRepo.insert()
    assert changeset.errors == [price: "price must be greater than 0"]
    assert changeset.model.__meta__.state == :built

    # When the change does not violate the check constraint
    changeset = Ecto.Changeset.change(%CheckConstraintModel{}, price: 10)
    {:ok, changeset} =
      changeset
      |> Ecto.Changeset.check_constraint(:price, name: :positive_price, message: "price must be greater than 0")
      |> TestRepo.insert()
    assert is_integer(changeset.id)

    assert :ok == down(TestRepo, 20120806000000, CheckConstraintMigration, log: false)
  end
end
