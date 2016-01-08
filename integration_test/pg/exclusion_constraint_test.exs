defmodule Ecto.Integration.ExclusionConstraintTest do
  use ExUnit.Case, async: true

  alias Ecto.Integration.TestRepo
  import Ecto.Migrator, only: [up: 4, down: 4]

  defmodule ExcludeConstraintMigration do
    use Ecto.Migration

    @table table(:non_overlapping_ranges)

    def change do
      create @table do
        add :from, :integer
        add :to, :integer
      end
      create constraint(@table.name, :cannot_overlap, exclude: ~s|gist (int4range("from", "to", '[]') WITH &&)|)
    end
  end

  defmodule ExcludeConstraintModel do
    use Ecto.Integration.Schema

    schema "non_overlapping_ranges" do
      field :from, :integer
      field :to, :integer
    end
  end

  test "creating, using, and dropping an exclude constraint" do
    assert :ok == up(TestRepo, 20050906120000, ExcludeConstraintMigration, log: false)

    changeset = Ecto.Changeset.change(%ExcludeConstraintModel{}, from: 0, to: 10)
    {:ok, _} = TestRepo.insert(changeset)

    non_overlapping_changeset = Ecto.Changeset.change(%ExcludeConstraintModel{}, from: 11, to: 12)
    {:ok, _} = TestRepo.insert(non_overlapping_changeset)

    overlapping_changeset = Ecto.Changeset.change(%ExcludeConstraintModel{}, from: 9, to: 12)

    exception =
      assert_raise Ecto.ConstraintError, ~r/constraint error when attempting to insert model/, fn ->
        overlapping_changeset
        |> TestRepo.insert()
      end
    assert exception.message =~ "exclude: cannot_overlap"
    assert exception.message =~ "The changeset has not defined any constraint."

    message = ~r/constraint error when attempting to insert model/
    exception =
      assert_raise Ecto.ConstraintError, message, fn ->
        overlapping_changeset
        |> Ecto.Changeset.exclude_constraint(:from)
        |> TestRepo.insert()
      end
    assert exception.message =~ "exclude: cannot_overlap"

    {:error, changeset} =
      overlapping_changeset
      |> Ecto.Changeset.exclude_constraint(:from, name: :cannot_overlap)
      |> TestRepo.insert()
    assert changeset.errors == [from: "violates an exclusion constraint"]
    assert changeset.model.__meta__.state == :built

    assert :ok == down(TestRepo, 20050906120000, ExcludeConstraintMigration, log: false)
  end
end
