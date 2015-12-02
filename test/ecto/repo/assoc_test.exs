defmodule Ecto.Repo.AssocTest do
  use ExUnit.Case, async: true

  import Ecto.Model, only: [put_meta: 2]
  require Ecto.TestRepo, as: TestRepo

  defmodule SubAssoc do
    use Ecto.Model

    schema "sub_assoc" do
      field :y, :string
      belongs_to :my_assoc, MyAssoc
    end
  end

  defmodule MyAssoc do
    use Ecto.Model

    schema "my_assoc" do
      field :x, :string
      has_one :sub_assoc, SubAssoc
      belongs_to :my_model, MyModel
      timestamps
    end
  end

  defmodule MyModel do
    use Ecto.Model

    schema "my_model" do
      field :x, :string
      field :y, :binary
      has_one :assoc, MyAssoc, on_replace: :delete
      has_many :assocs, MyAssoc, on_replace: :delete
    end
  end

  test "handles assocs on insert" do
    sample = %MyAssoc{x: "xyz"}

    changeset = Ecto.Changeset.change(%MyModel{}, assoc: sample)
    model = TestRepo.insert!(changeset)
    assoc = model.assoc
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.my_model_id == model.id
    assert assoc.inserted_at

    changeset = Ecto.Changeset.change(%MyModel{}, assocs: [sample])
    model = TestRepo.insert!(changeset)
    [assoc] = model.assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.my_model_id == model.id
    assert assoc.inserted_at
  end

  test "raises when assoc is given on insert" do
    assert_raise ArgumentError, ~r"set for assoc named `assoc`", fn ->
      TestRepo.insert!(%MyModel{assoc: %MyAssoc{x: "xyz"}})
    end

    assert_raise ArgumentError, ~r"set for assoc named `assocs`", fn ->
      TestRepo.insert!(%MyModel{assocs: [%MyAssoc{x: "xyz"}]})
    end
  end

  test "raises on action mismatch on insert" do
    changeset = Ecto.Changeset.change(%MyModel{}, assoc: %MyAssoc{x: "xyz"})
    changeset = put_in(changeset.changes.assoc.action, :delete)
    assert_raise ArgumentError, ~r"got action :delete in changeset for associated .* while inserting", fn ->
      TestRepo.insert!(changeset)
    end
  end

  test "returns untouched changeset on invalid children on insert" do
    assoc = %MyAssoc{x: "xyz"}
    assoc_changeset = %{Ecto.Changeset.change(assoc) | valid?: false}
    changeset = Ecto.Changeset.change(%MyModel{}, assoc: assoc_changeset)
    assert {:error, changeset} = TestRepo.insert(changeset)
    assert_received {:rollback, ^changeset}
    refute changeset.valid?
  end

  test "fails cleanly for bad assocs on insert" do
    assoc = Ecto.Changeset.change(%MyAssoc{})
            |> Ecto.Changeset.put_change(:x, "xyz")
            |> Ecto.Changeset.put_change(:my_model, %MyModel{})

    assert_raise ArgumentError, ~r/cannot insert `my_model` in Ecto.Repo.AssocTest.MyAssoc/, fn ->
      TestRepo.insert!(assoc)
    end
  end

  test "returns untouched changeset on parent constraint mismatch on insert" do
    assoc_changeset = Ecto.Changeset.change(%MyAssoc{x: "xyz"})

    changeset =
      put_in(%MyModel{}.__meta__.context, {:invalid, [unique: "my_model_foo_index"]})
      |> Ecto.Changeset.change(assoc: assoc_changeset)
      |> Ecto.Changeset.unique_constraint(:foo)
    assert {:error, changeset} = TestRepo.insert(changeset)
    assert_received {:rollback, ^changeset}
    assert changeset.model.__meta__.state == :built
    assert %Ecto.Association.NotLoaded{} = changeset.model.assoc
    assert changeset.changes.assoc
    refute changeset.changes.assoc.model.id
    refute changeset.valid?
  end

  test "returns untouched changeset on child constraint mismatch on insert" do
    assoc_changeset =
      put_in(%MyAssoc{}.__meta__.context, {:invalid, [unique: "my_assoc_foo_index"]})
      |> Ecto.Changeset.change
      |> Ecto.Changeset.unique_constraint(:foo)

    changeset = Ecto.Changeset.change(%MyModel{}, assoc: assoc_changeset)
    assert {:error, changeset} = TestRepo.insert(changeset)
    assert changeset.model.__meta__.state == :built
    assert %Ecto.Association.NotLoaded{} = changeset.model.assoc
    assert changeset.changes.assoc
    refute changeset.changes.assoc.model.id
    refute changeset.valid?

    # Just one transaction was used
    assert_received {:transaction, _}
    assert_received {:rollback, ^changeset}
    refute_received {:transaction, _}
    refute_received {:rollback, _}
  end

  test "handles valid nested assocs on insert" do
    assoc = Ecto.Changeset.change(%MyAssoc{x: "xyz"}, sub_assoc: %SubAssoc{y: "xyz"})
    changeset = Ecto.Changeset.change(%MyModel{}, assoc: assoc)
    model = TestRepo.insert!(changeset)
    assert model.assoc.sub_assoc.id

    # Just one transaction was used
    assert_received {:transaction, _}
    refute_received {:rollback, _}
  end

  test "handles invalid nested assocs on insert" do
    sub_assoc_change = %{Ecto.Changeset.change(%SubAssoc{y: "xyz"}) | valid?: false}
    assoc = Ecto.Changeset.change(%MyAssoc{x: "xyz"}, sub_assoc: sub_assoc_change)
    changeset = Ecto.Changeset.change(%MyModel{}, assoc: assoc)
    assert {:error, changeset} = TestRepo.insert(changeset)
    refute changeset.changes.id
    refute changeset.changes.assoc.changes.id
    refute changeset.changes.assoc.changes.my_model_id
    refute changeset.changes.assoc.changes.sub_assoc.changes.id
    refute changeset.changes.assoc.changes.sub_assoc.changes.my_assoc_id
    refute changeset.valid?

    # Just one transaction was used
    assert_received {:transaction, _}
    assert_received {:rollback, ^changeset}
    refute_received {:transaction, _}
    refute_received {:rollback, _}
  end

  test "skips assocs on update when not changing" do
    assoc = %MyAssoc{x: "xyz"}

    # If assoc is not in changeset, assocs are left out
    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: assoc}, x: "abc")
    model = TestRepo.update!(changeset)
    assert model.assoc == assoc

    changeset = Ecto.Changeset.change(%MyModel{id: 1, assocs: [assoc]}, x: "abc")
    model = TestRepo.update!(changeset)
    assert model.assocs == [assoc]
  end

  test "inserting assocs on update" do
    sample = %MyAssoc{x: "xyz"}

    changeset = Ecto.Changeset.change(%MyModel{id: 1}, assoc: sample)
    model = TestRepo.update!(changeset)
    assoc = model.assoc
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.my_model_id == model.id
    assert assoc.updated_at

    changeset = Ecto.Changeset.change(%MyModel{id: 1}, assocs: [sample])
    model = TestRepo.update!(changeset)
    [assoc] = model.assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.my_model_id == model.id
    assert assoc.updated_at
  end

  test "replacing assocs on update" do
    sample = %MyAssoc{id: 10, x: "xyz"}

    # Replacing assoc with a new one
    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: sample}, assoc: %MyAssoc{x: "abc"})
    model = TestRepo.update!(changeset)
    assoc = model.assoc
    assert assoc.id != 10
    assert assoc.x == "abc"
    assert assoc.my_model_id == model.id
    assert assoc.updated_at

    # Replacing assoc with nil
    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: sample}, assoc: nil)
    model = TestRepo.update!(changeset)
    refute model.assoc
  end

  test "changing assocs on update raises if there is no id" do
    sample = %MyAssoc{x: "xyz"}
    sample_changeset = Ecto.Changeset.change(sample, x: "abc")

    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: sample}, assoc: sample_changeset)
    assert_raise Ecto.NoPrimaryKeyValueError, fn ->
      TestRepo.update!(changeset)
    end
  end

  test "changing assocs on update" do
    sample = %MyAssoc{x: "xyz", id: 13, my_model: 1, sub_assoc: nil}
    sample = put_meta sample, state: :loaded

    # Changing the assoc
    sample_changeset = Ecto.Changeset.change(sample, x: "abc")
    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: sample}, assoc: sample_changeset)
    model = TestRepo.update!(changeset)
    assoc = model.assoc
    assert assoc.id == 13
    assert assoc.x == "abc"
    refute assoc.inserted_at
    assert assoc.updated_at

    changeset = Ecto.Changeset.change(%MyModel{id: 1, assocs: [sample]}, assocs: [sample_changeset])
    model = TestRepo.update!(changeset)
    [assoc] = model.assocs
    assert assoc.id == 13
    assert assoc.x == "abc"
    refute assoc.inserted_at
    assert assoc.updated_at
  end

  test "removing assocs on update raises if there is no id" do
    assoc = %MyAssoc{x: "xyz"}

    # Raises if there's no id
    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: assoc}, assoc: nil)
    assert_raise Ecto.NoPrimaryKeyValueError, fn ->
      TestRepo.update!(changeset)
    end
  end

  test "removing assocs on update" do
    assoc = %MyAssoc{x: "xyz", id: 1}

    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: assoc}, assoc: nil)
    model = TestRepo.update!(changeset)
    assert model.assoc == nil

    changeset = Ecto.Changeset.change(%MyModel{id: 1, assocs: [assoc]}, assocs: [])
    model = TestRepo.update!(changeset)
    assert model.assocs == []
  end

  test "returns untouched changeset on invalid children on update" do
    assoc = %MyAssoc{x: "xyz"}
    assoc_changeset = %{Ecto.Changeset.change(assoc) | valid?: false}
    changeset = Ecto.Changeset.change(%MyModel{id: 1}, assoc: assoc_changeset)
    assert {:error, changeset} = TestRepo.update(changeset)
    assert_received {:rollback, ^changeset}
    refute changeset.valid?
  end

  test "returns untouched changeset on constraint mismatch on update" do
    my_model = %MyModel{id: 1, assoc: nil}
    changeset =
      put_in(my_model.__meta__.context, {:invalid, [unique: "my_model_foo_index"]})
      |> Ecto.Changeset.change(assoc: %MyAssoc{x: "xyz"}, x: "foo")
      |> Ecto.Changeset.unique_constraint(:foo)
    assert {:error, changeset} = TestRepo.update(changeset)
    assert_received {:rollback, ^changeset}
    refute changeset.model.assoc
    assert changeset.changes.assoc
    refute changeset.changes.assoc.model.id
    refute changeset.valid?
  end

  test "handles valid nested assocs on update" do
    assoc = %MyAssoc{id: 1, x: "xyz"}
    assoc_changeset = Ecto.Changeset.change(assoc, sub_assoc: %SubAssoc{y: "xyz"})
    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: assoc}, assoc: assoc_changeset)
    model = TestRepo.update!(changeset)
    assert model.assoc.sub_assoc.id

    # One transaction was used
    assert_received {:transaction, _}
    refute_received {:rollback, _}
  end

  test "handles invalid nested assocs on update" do
    sub_assoc = %SubAssoc{y: "xyz"}
    sub_assoc_change = %{Ecto.Changeset.change(sub_assoc) | valid?: false}
    assoc = %MyAssoc{id: 1, x: "xyz"}
    assoc_changeset = Ecto.Changeset.change(assoc, sub_assoc: sub_assoc_change)
    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: assoc}, assoc: assoc_changeset)
    assert {:error, changeset} = TestRepo.update(changeset)
    refute changeset.changes.assoc.changes.sub_assoc.changes.id
    refute changeset.changes.assoc.changes.sub_assoc.changes.my_assoc_id
    refute changeset.valid?

    # Just one transaction was used
    assert_received {:transaction, _}
    assert_received {:rollback, ^changeset}
    refute_received {:transaction, _}
    refute_received {:rollback, _}
  end
end
