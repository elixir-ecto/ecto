defmodule Ecto.Repo.HasAssocTest do
  use ExUnit.Case, async: true

  import Ecto, only: [put_meta: 2]
  require Ecto.TestRepo, as: TestRepo

  defmodule SubAssoc do
    use Ecto.Schema

    schema "sub_assoc" do
      field :y, :string
      belongs_to :my_assoc, MyAssoc
    end
  end

  defmodule MyAssoc do
    use Ecto.Schema

    schema "my_assoc" do
      field :x, :string
      has_one :sub_assoc, SubAssoc
      belongs_to :my_model, MyModel
      timestamps
    end
  end

  defmodule MyModel do
    use Ecto.Schema

    schema "my_model" do
      field :x, :string
      field :y, :binary
      has_one :assoc, MyAssoc, on_replace: :delete
      has_one :nilify_assoc, MyAssoc, on_replace: :nilify
      has_many :assocs, MyAssoc, on_replace: :delete
    end
  end

  test "handles assocs on insert" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MyModel{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, sample)
    model = TestRepo.insert!(changeset)
    assoc = model.assoc
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.my_model_id == model.id
    assert assoc.inserted_at

    changeset =
      %MyModel{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [sample])
    model = TestRepo.insert!(changeset)
    [assoc] = model.assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.my_model_id == model.id
    assert assoc.inserted_at
  end

  test "handles assocs from struct on insert" do
    model = TestRepo.insert!(%MyModel{assoc: %MyAssoc{x: "xyz"}})
    assoc = model.assoc
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.my_model_id == model.id
    assert assoc.inserted_at

    model = TestRepo.insert!(%MyModel{assocs: [%MyAssoc{x: "xyz"}]})
    [assoc] = model.assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.my_model_id == model.id
    assert assoc.inserted_at
  end

  test "handles invalid assocs from struct on insert" do
    {:error, changeset} = TestRepo.insert(%MyModel{assoc: 1})
    assert changeset.errors == [assoc: "is invalid"]
  end

  test "raises on action mismatch on insert" do
    changeset =
      %MyModel{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, %MyAssoc{x: "xyz"})
    changeset = put_in(changeset.changes.assoc.action, :delete)
    assert_raise ArgumentError, ~r"got action :delete in changeset for associated .* while inserting", fn ->
      TestRepo.insert!(changeset)
    end
  end

  test "returns untouched changeset on invalid children on insert" do
    assoc = %MyAssoc{x: "xyz"}
    assoc_changeset = %{Ecto.Changeset.change(assoc) | valid?: false}
    changeset =
      %MyModel{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, assoc_changeset)
    assert {:error, changeset} = TestRepo.insert(%{changeset | valid?: true})
    assert_received {:rollback, ^changeset}
    refute changeset.valid?
  end

  test "returns untouched changeset on parent constraint mismatch on insert" do
    assoc_changeset = Ecto.Changeset.change(%MyAssoc{x: "xyz"})

    changeset =
      put_in(%MyModel{}.__meta__.context, {:invalid, [unique: "my_model_foo_index"]})
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, assoc_changeset)
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

    changeset =
      %MyModel{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, assoc_changeset)
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
    assoc =
      %MyAssoc{x: "xyz"}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:sub_assoc, %SubAssoc{y: "xyz"})
    changeset =
      %MyModel{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, assoc)
    model = TestRepo.insert!(changeset)
    assert model.assoc.sub_assoc.id

    # Just one transaction was used
    assert_received {:transaction, _}
    refute_received {:rollback, _}
  end

  test "handles invalid nested assocs on insert" do
    sub_assoc_change = %{Ecto.Changeset.change(%SubAssoc{y: "xyz"}) | valid?: false}
    assoc =
      %MyAssoc{x: "xyz"}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:sub_assoc, sub_assoc_change)
    changeset =
      %MyModel{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, assoc)
    assert {:error, changeset} = TestRepo.insert(%{changeset | valid?: true})
    refute Map.has_key?(changeset.changes, :id)
    refute changeset.changes.assoc.changes.my_model_id
    refute Map.has_key?(changeset.changes.assoc.changes, :id)
    refute Map.has_key?(changeset.changes.assoc.changes.sub_assoc.changes, :id)
    refute Map.has_key?(changeset.changes.assoc.changes.sub_assoc.changes, :my_assoc_id)
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

    changeset =
      %MyModel{id: 1}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, sample)
    model = TestRepo.update!(changeset)
    assoc = model.assoc
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.my_model_id == model.id
    assert assoc.updated_at

    changeset =
      %MyModel{id: 1}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [sample])
    model = TestRepo.update!(changeset)
    [assoc] = model.assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.my_model_id == model.id
    assert assoc.updated_at
  end

  test "replacing assocs on update on_replace: :delete" do
    sample = %MyAssoc{id: 10, x: "xyz"} |> Ecto.put_meta(state: :loaded)

    # Replacing assoc with a new one
    changeset =
      %MyModel{id: 1, assoc: sample}
      |> Ecto.Changeset.change(x: "1")
      |> Ecto.Changeset.put_assoc(:assoc, %MyAssoc{x: "abc"})
    model = TestRepo.update!(changeset)
    assoc = model.assoc
    assert assoc.id != 10
    assert assoc.x == "abc"
    assert assoc.my_model_id == model.id
    assert assoc.updated_at
    assert_received :update # Parent
    assert_received :insert # New assoc
    assert_received :delete # Old assoc

    # Replacing assoc with nil
    changeset =
      %MyModel{id: 1, assoc: sample}
      |> Ecto.Changeset.change(x: "2")
      |> Ecto.Changeset.put_assoc(:assoc, nil)
    model = TestRepo.update!(changeset)
    refute model.assoc
    assert_received :update # Parent
    refute_received :insert # New assoc
    assert_received :delete # Old assoc
  end

  test "replacing assocs on update on_replace: :nilify" do
    sample = %MyAssoc{id: 10, my_model_id: 1, x: "xyz"} |> Ecto.put_meta(state: :loaded)

    # Replacing assoc with a new one
    changeset =
      %MyModel{id: 1, nilify_assoc: sample}
      |> Ecto.Changeset.change(x: "1")
      |> Ecto.Changeset.put_assoc(:nilify_assoc, %MyAssoc{x: "abc"})
    model = TestRepo.update!(changeset)
    assoc = model.nilify_assoc
    assert assoc.id != 10
    assert assoc.x == "abc"
    assert assoc.my_model_id == model.id
    assert assoc.updated_at
    assert_received :update # Parent
    assert_received :insert # New assoc
    assert_received :update # Old assoc

    # Replacing assoc with nil
    changeset =
      %MyModel{id: 1, nilify_assoc: sample}
      |> Ecto.Changeset.change(x: "2")
      |> Ecto.Changeset.put_assoc(:nilify_assoc, nil)
    model = TestRepo.update!(changeset)
    refute model.nilify_assoc
    assert_received :update # Parent
    refute_received :insert # New assoc
    assert_received :update # Old assoc
  end

  test "changing assocs on update raises if there is no id" do
    sample = %MyAssoc{x: "xyz"} |> Ecto.put_meta(state: :loaded)
    sample_changeset = Ecto.Changeset.change(sample, x: "abc")

    changeset =
      %MyModel{id: 1, assoc: sample}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, sample_changeset)
    assert_raise Ecto.NoPrimaryKeyValueError, fn ->
      TestRepo.update!(changeset)
    end
  end

  test "changing assocs on update" do
    sample = %MyAssoc{x: "xyz", id: 13, my_model: 1, sub_assoc: nil}
    sample = put_meta sample, state: :loaded

    # Changing the assoc
    sample_changeset = Ecto.Changeset.change(sample, x: "abc")
    changeset =
      %MyModel{id: 1, assoc: sample}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, sample_changeset)
    model = TestRepo.update!(changeset)
    assoc = model.assoc
    assert assoc.id == 13
    assert assoc.x == "abc"
    refute assoc.inserted_at
    assert assoc.updated_at
    refute_received :delete # Same assoc should not emit delete

    changeset =
      %MyModel{id: 1, assocs: [sample]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [sample_changeset])
    model = TestRepo.update!(changeset)
    [assoc] = model.assocs
    assert assoc.id == 13
    assert assoc.x == "abc"
    refute assoc.inserted_at
    assert assoc.updated_at
    refute_received :delete # Same assoc should not emit delete
  end

  test "removing assocs on update raises if there is no id" do
    assoc = %MyAssoc{x: "xyz"} |> Ecto.put_meta(state: :loaded)

    # Raises if there's no id
    changeset =
      %MyModel{id: 1, assoc: assoc}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, nil)
    assert_raise Ecto.NoPrimaryKeyValueError, fn ->
      TestRepo.update!(changeset)
    end
  end

  test "removing assocs on update" do
    assoc = %MyAssoc{x: "xyz", id: 1}

    changeset =
      %MyModel{id: 1, assoc: assoc}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, nil)
    model = TestRepo.update!(changeset)
    assert model.assoc == nil

    changeset =
      %MyModel{id: 1, assocs: [assoc]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [])
    model = TestRepo.update!(changeset)
    assert model.assocs == []
  end

  test "returns untouched changeset on invalid children on update" do
    assoc = %MyAssoc{x: "xyz"}
    assoc_changeset = %{Ecto.Changeset.change(assoc) | valid?: false}
    changeset =
      %MyModel{id: 1}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, assoc_changeset)
    assert {:error, changeset} = TestRepo.update(%{changeset | valid?: true})
    assert_received {:rollback, ^changeset}
    refute changeset.valid?
  end

  test "returns untouched changeset on constraint mismatch on update" do
    my_model = %MyModel{id: 1, assoc: nil}
    changeset =
      put_in(my_model.__meta__.context, {:invalid, [unique: "my_model_foo_index"]})
      |> Ecto.Changeset.change(x: "foo")
      |> Ecto.Changeset.put_assoc(:assoc, %MyAssoc{x: "xyz"})
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
    assoc_changeset =
      assoc
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:sub_assoc, %SubAssoc{y: "xyz"})
    changeset =
      %MyModel{id: 1, assoc: assoc}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, assoc_changeset)
    model = TestRepo.update!(changeset)
    assert model.assoc.sub_assoc.id

    # One transaction was used
    assert_received {:transaction, _}
    refute_received {:rollback, _}
  end

  test "handles invalid nested assocs on update" do
    sub_assoc = %SubAssoc{y: "xyz"}
    sub_assoc_changeset = %{Ecto.Changeset.change(sub_assoc) | valid?: false}

    assoc = %MyAssoc{id: 1, x: "xyz"}
    assoc_changeset =
      assoc
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:sub_assoc, sub_assoc_changeset)

    changeset =
      %MyModel{id: 1, assoc: assoc}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, assoc_changeset)

    assert {:error, changeset} = TestRepo.update(%{changeset | valid?: true})
    refute Map.has_key?(changeset.changes.assoc.changes.sub_assoc.changes, :id)
    refute Map.has_key?(changeset.changes.assoc.changes.sub_assoc.changes, :my_assoc_id)
    refute changeset.valid?

    # Just one transaction was used
    assert_received {:transaction, _}
    assert_received {:rollback, ^changeset}
    refute_received {:transaction, _}
    refute_received {:rollback, _}
  end
end
