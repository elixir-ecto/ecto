defmodule Ecto.Repo.ManyToManyTest do
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
      timestamps
    end
  end

  defmodule MyModelAssoc do
    use Ecto.Schema

    schema "models_assocs" do
      belongs_to :my_model, MyModel
      belongs_to :my_assoc, MyAssoc
      timestamps
    end
  end

  defmodule MyModel do
    use Ecto.Schema

    schema "my_model" do
      field :x, :string
      field :y, :binary
      many_to_many :assocs, MyAssoc, join_through: "models_assocs", on_replace: :delete
      many_to_many :schema_assocs, MyAssoc, join_through: MyModelAssoc
    end
  end

  test "handles assocs on insert" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MyModel{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [sample])
    model = TestRepo.insert!(changeset)
    [assoc] = model.assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.inserted_at
    assert_received :insert
    assert_received {:insert_all, "models_assocs", [[my_model_id: 1, my_assoc_id: 1]]}
  end

  test "handles assocs on insert with schema" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MyModel{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:schema_assocs, [sample])
    model = TestRepo.insert!(changeset)
    [assoc] = model.schema_assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.inserted_at
    assert_received :insert
    assert_received :insert
  end

  test "handles assocs from struct on insert" do
    model = TestRepo.insert!(%MyModel{assocs: [%MyAssoc{x: "xyz"}]})
    [assoc] = model.assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.inserted_at
    assert_received :insert
    assert_received {:insert_all, "models_assocs", [[my_model_id: 1, my_assoc_id: 1]]}
  end

  test "handles invalid assocs from struct on insert" do
    {:error, changeset} = TestRepo.insert(%MyModel{assocs: [1]})
    assert changeset.errors == [assocs: "is invalid"]
  end

  test "raises on action mismatch on insert" do
    assoc = %{Ecto.Changeset.change(%MyAssoc{x: "xyz"}) | action: :delete}

    changeset =
      %MyModel{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [assoc])

    assert_raise ArgumentError, ~r"got action :delete in changeset for associated .* while inserting", fn ->
      TestRepo.insert!(changeset)
    end
  end

  test "returns untouched changeset on invalid children on insert" do
    assoc = %{Ecto.Changeset.change(%MyAssoc{x: "xyz"}) | valid?: false}

    changeset =
      %MyModel{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [assoc])

    assert {:error, changeset} = TestRepo.insert(%{changeset | valid?: true})
    assert_received {:rollback, ^changeset}
    refute changeset.valid?
  end

  test "returns untouched changeset on parent constraint mismatch on insert" do
    assoc = Ecto.Changeset.change(%MyAssoc{x: "xyz"})

    changeset =
      put_in(%MyModel{}.__meta__.context, {:invalid, [unique: "my_model_foo_index"]})
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [assoc])
      |> Ecto.Changeset.unique_constraint(:foo)
    assert {:error, changeset} = TestRepo.insert(changeset)
    assert_received {:rollback, ^changeset}
    assert changeset.model.__meta__.state == :built
    assert %Ecto.Association.NotLoaded{} = changeset.model.assocs
    assert changeset.changes.assocs
    refute hd(changeset.changes.assocs).model.id
    refute changeset.valid?
  end

  test "returns untouched changeset on child constraint mismatch on insert" do
    assoc =
      put_in(%MyAssoc{}.__meta__.context, {:invalid, [unique: "my_assoc_foo_index"]})
      |> Ecto.Changeset.change
      |> Ecto.Changeset.unique_constraint(:foo)

    changeset =
      %MyModel{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [assoc])
    assert {:error, changeset} = TestRepo.insert(changeset)
    assert changeset.model.__meta__.state == :built
    assert %Ecto.Association.NotLoaded{} = changeset.model.assocs
    assert changeset.changes.assocs
    refute hd(changeset.changes.assocs).model.id
    refute changeset.valid?

    # Just one transaction was used
    assert_received {:transaction, _}
    assert_received {:rollback, ^changeset}
    refute_received {:transaction, _}
    refute_received {:rollback, _}
    refute_received {:insert_all, _, _}
  end

  test "handles valid nested assocs on insert" do
    assoc =
      %MyAssoc{x: "xyz"}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:sub_assoc, %SubAssoc{y: "xyz"})
    changeset =
      %MyModel{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [assoc])
    model = TestRepo.insert!(changeset)
    assert hd(model.assocs).sub_assoc.id

    # Just one transaction was used
    assert_received {:transaction, _}
    refute_received {:rollback, _}
    assert_received {:insert_all, "models_assocs", [[my_model_id: 1, my_assoc_id: 1]]}
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
      |> Ecto.Changeset.put_assoc(:assocs, [assoc])
    assert {:error, changeset} = TestRepo.insert(%{changeset | valid?: true})
    refute Map.has_key?(changeset.changes, :id)
    refute changeset.valid?

    [assoc] = changeset.changes.assocs
    refute Map.has_key?(assoc.changes, :id)
    refute Map.has_key?(assoc.changes.sub_assoc.changes, :id)

    # Just one transaction was used
    assert_received {:transaction, _}
    assert_received {:rollback, ^changeset}
    refute_received {:transaction, _}
    refute_received {:rollback, _}
    refute_received {:insert_all, _, _}
  end

  test "skips assocs on update when not changing" do
    assoc = %MyAssoc{x: "xyz"}

    # If assoc is not in changeset, assocs are left out
    changeset = Ecto.Changeset.change(%MyModel{id: 1, assocs: [assoc]}, x: "abc")
    model = TestRepo.update!(changeset)
    assert model.assocs == [assoc]
  end

  test "inserting assocs on update" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MyModel{id: 3}
      |> Ecto.Changeset.change(x: "1")
      |> Ecto.Changeset.put_assoc(:assocs, [sample])
    model = TestRepo.update!(changeset)
    [assoc] = model.assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.updated_at
    assert_received :update
    assert_received {:insert_all, "models_assocs", [[my_model_id: 3, my_assoc_id: 1]]}
  end

  test "inserting assocs on update with schema" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MyModel{id: 3}
      |> Ecto.Changeset.change(x: "1")
      |> Ecto.Changeset.put_assoc(:schema_assocs, [sample])
    model = TestRepo.update!(changeset)
    [assoc] = model.schema_assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.updated_at
    assert_received :update
    assert_received :insert
  end

  test "replacing assocs on update on_replace" do
    sample = %MyAssoc{id: 10, x: "xyz"} |> Ecto.put_meta(state: :loaded)

    # Replacing assoc with a new one
    changeset =
      %MyModel{id: 3, assocs: [sample]}
      |> Ecto.Changeset.change(x: "1")
      |> Ecto.Changeset.put_assoc(:assocs, [%MyAssoc{x: "abc"}])
    model = TestRepo.update!(changeset)
    [assoc] = model.assocs
    assert assoc.id != 10
    assert assoc.x == "abc"
    assert assoc.updated_at
    assert_received :update # Parent
    assert_received :insert # New assoc
    refute_received :delete # Old assoc
    assert_received {:insert_all, "models_assocs", [[my_model_id: 3, my_assoc_id: 1]]}
    assert_received {:delete_all, "models_assocs"}

    # Replacing assoc with nil
    changeset =
      %MyModel{id: 1, assocs: [sample]}
      |> Ecto.Changeset.change(x: "2")
      |> Ecto.Changeset.put_assoc(:assocs, [])
    model = TestRepo.update!(changeset)
    assert model.assocs == []
    assert_received :update # Parent
    refute_received :insert # New assoc
    refute_received :delete # Old assoc
    refute_received {:insert_all, _, _}
    assert_received {:delete_all, _}
  end

  test "changing assocs on update raises if there is no id" do
    sample = %MyAssoc{x: "xyz"} |> Ecto.put_meta(state: :loaded)
    sample_changeset = Ecto.Changeset.change(sample, x: "abc")

    changeset =
      %MyModel{id: 1, assocs: [sample]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [sample_changeset])
    assert_raise Ecto.NoPrimaryKeyValueError, fn ->
      TestRepo.update!(changeset)
    end
  end

  test "changing assocs on update" do
    sample = %MyAssoc{x: "xyz", id: 13, sub_assoc: nil}
    sample = put_meta sample, state: :loaded

    # Changing the assoc
    sample_changeset = Ecto.Changeset.change(sample, x: "abc")
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
    refute_received {:delete_all, _}
    refute_received {:insert_all, _, _}
  end

  test "removing assocs on update raises if there is no id" do
    assoc = %MyAssoc{x: "xyz"} |> Ecto.put_meta(state: :loaded)

    # Raises if there's no id
    changeset =
      %MyModel{id: 1, assocs: [assoc]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [])
    assert_raise RuntimeError,  ~r/could not delete join entry because `id` is nil/, fn ->
      TestRepo.update!(changeset)
    end
  end

  test "removing assocs on update" do
    assoc = %MyAssoc{x: "xyz", id: 1}

    changeset =
      %MyModel{id: 1, assocs: [assoc]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [])
    model = TestRepo.update!(changeset)
    assert model.assocs == []
    assert_received {:delete_all, "models_assocs"}
  end

  test "returns untouched changeset on invalid children on update" do
    assoc = %MyAssoc{x: "xyz"}
    assoc_changeset = %{Ecto.Changeset.change(assoc) | valid?: false}
    changeset =
      %MyModel{id: 1}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [assoc_changeset])
    assert {:error, changeset} = TestRepo.update(%{changeset | valid?: true})
    assert_received {:rollback, ^changeset}
    refute changeset.valid?
  end

  test "returns untouched changeset on constraint mismatch on update" do
    my_model = %MyModel{id: 1, assocs: []}

    changeset =
      put_in(my_model.__meta__.context, {:invalid, [unique: "my_model_foo_index"]})
      |> Ecto.Changeset.change(x: "foo")
      |> Ecto.Changeset.put_assoc(:assocs, [%MyAssoc{x: "xyz"}])
      |> Ecto.Changeset.unique_constraint(:foo)
    assert {:error, changeset} = TestRepo.update(changeset)
    assert_received {:rollback, ^changeset}
    assert changeset.model.assocs == []
    refute changeset.valid?

    [assoc] = changeset.changes.assocs
    refute assoc.model.id
  end

  test "handles valid nested assocs on update" do
    assoc = %MyAssoc{id: 1, x: "xyz"}
    assoc_changeset =
      assoc
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:sub_assoc, %SubAssoc{y: "xyz"})
    changeset =
      %MyModel{id: 1, assocs: [assoc]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [assoc_changeset])
    model = TestRepo.update!(changeset)
    assert hd(model.assocs).sub_assoc.id

    # One transaction was used
    assert_received {:transaction, _}
    refute_received {:rollback, _}
    refute_received {:insert_all, _, _}
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
      %MyModel{id: 1, assocs: [assoc]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [assoc_changeset])

    assert {:error, changeset} = TestRepo.update(%{changeset | valid?: true})
    refute changeset.valid?

    [assoc] = changeset.changes.assocs
    refute Map.has_key?(assoc.changes.sub_assoc.changes, :id)
    refute Map.has_key?(assoc.changes.sub_assoc.changes, :my_assoc_id)

    # Just one transaction was used
    assert_received {:transaction, _}
    assert_received {:rollback, ^changeset}
    refute_received {:transaction, _}
    refute_received {:rollback, _}
    refute_received {:insert_all, _, _}
  end
end
