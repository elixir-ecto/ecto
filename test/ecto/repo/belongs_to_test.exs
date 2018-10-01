defmodule Ecto.Repo.BelongsToTest do
  use ExUnit.Case, async: true

  import Ecto, only: [put_meta: 2]
  require Ecto.TestRepo, as: TestRepo

  defmodule SubAssoc do
    use Ecto.Schema

    schema "sub_assoc" do
      field :y, :string
      has_one :my_assoc, MyAssoc
    end
  end

  defmodule MyAssoc do
    use Ecto.Schema

    schema "my_assoc" do
      field :x, :string
      belongs_to :sub_assoc, SubAssoc
      has_one :my_schema, MySchema
      timestamps()
    end
  end

  defmodule MySchema do
    use Ecto.Schema

    schema "my_schema" do
      field :x, :string
      field :y, :binary
      belongs_to :assoc, MyAssoc, on_replace: :delete
      belongs_to :nilify_assoc, MyAssoc, on_replace: :nilify
    end
  end

  test "handles assocs on insert" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MySchema{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, sample)
    schema = TestRepo.insert!(changeset)
    assoc = schema.assoc
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.id == schema.assoc_id
    assert assoc.inserted_at
  end

  test "handles assocs on insert preserving parent schema prefix" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MySchema{}
      |> Ecto.put_meta(prefix: "prefix")
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, sample)
    schema = TestRepo.insert!(changeset)
    assoc = schema.assoc
    assert assoc.__meta__.prefix == "prefix"
  end

  test "handles assocs from struct on insert" do
    schema = TestRepo.insert!(%MySchema{assoc: %MyAssoc{x: "xyz"}})
    assoc = schema.assoc
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.id == schema.assoc_id
    assert assoc.inserted_at
  end

  test "handles invalid assocs from struct on insert" do
    {:error, changeset} = TestRepo.insert(%MySchema{assoc: 1})
    assert changeset.errors == [assoc: {"is invalid", [type: :map]}]
  end

  test "raises on action mismatch on insert" do
    changeset =
      %MySchema{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, %MyAssoc{x: "xyz"})
    changeset = put_in(changeset.changes.assoc.action, :delete)
    assert_raise ArgumentError, ~r"got action :delete in changeset for associated .* while inserting", fn ->
      TestRepo.insert!(changeset)
    end
  end

  test "checks dual changes on insert" do
    # values are the same
    changeset =
      %MySchema{}
      |> Ecto.Changeset.change(assoc_id: 13)
      |> Ecto.Changeset.put_assoc(:assoc, %MyAssoc{x: "xyz", id: 13})
    TestRepo.insert!(changeset)

    # values are different
    changeset =
      %MySchema{}
      |> Ecto.Changeset.change(assoc_id: 13)
      |> Ecto.Changeset.put_assoc(:assoc, %MyAssoc{x: "xyz"})
    assert_raise ArgumentError, ~r"there is already a change setting its foreign key", fn ->
      TestRepo.insert!(changeset)
    end
  end

  test "returns untouched changeset on invalid children on insert" do
    assoc = %MyAssoc{x: "xyz"}
    assoc_changeset = %{Ecto.Changeset.change(assoc) | valid?: false}
    changeset =
      %MySchema{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, assoc_changeset)
    assert {:error, changeset} = TestRepo.insert(%{changeset | valid?: true})
    assert_received {:rollback, ^changeset}
    refute changeset.valid?
  end

  test "returns untouched changeset on parent constraint mismatch on insert" do
    assoc_changeset = Ecto.Changeset.change(%MyAssoc{x: "xyz"})

    changeset =
      put_in(%MySchema{}.__meta__.context, {:invalid, [unique: "my_schema_foo_index"]})
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, assoc_changeset)
      |> Ecto.Changeset.unique_constraint(:foo)
    assert {:error, changeset} = TestRepo.insert(changeset)
    assert_received {:rollback, ^changeset}
    assert changeset.data.__meta__.state == :built
    assert %Ecto.Association.NotLoaded{} = changeset.data.assoc
    assert changeset.changes.assoc
    refute changeset.changes.assoc.data.id
    refute changeset.valid?
  end

  test "returns untouched changeset on child constraint mismatch on insert" do
    assoc_changeset =
      put_in(%MyAssoc{}.__meta__.context, {:invalid, [unique: "my_assoc_foo_index"]})
      |> Ecto.Changeset.change
      |> Ecto.Changeset.unique_constraint(:foo)

    changeset =
      %MySchema{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, assoc_changeset)
    assert {:error, changeset} = TestRepo.insert(changeset)
    assert changeset.data.__meta__.state == :built
    assert %Ecto.Association.NotLoaded{} = changeset.data.assoc
    assert changeset.changes.assoc
    refute changeset.changes.assoc.data.id
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
      %MySchema{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, assoc)
    schema = TestRepo.insert!(changeset)
    assert schema.assoc.sub_assoc.id
    assert schema.assoc_id == schema.assoc.id
    assert schema.assoc.sub_assoc_id == schema.assoc.sub_assoc.id

    # Just one transaction was used
    assert_received {:transaction, _}
    refute_received {:rollback, _}
  end

  test "handles valid nested assocs on insert preserving parent schema prefix" do
    assoc =
      %MyAssoc{x: "xyz"}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:sub_assoc, %SubAssoc{y: "xyz"})
    changeset =
      %MySchema{}
      |> Ecto.put_meta(prefix: "prefix")
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, assoc)
    schema = TestRepo.insert!(changeset)

    assert schema.assoc.sub_assoc.__meta__.prefix == "prefix"
  end

  test "handles invalid nested assocs on insert" do
    sub_assoc_change = %{Ecto.Changeset.change(%SubAssoc{y: "xyz"}) | valid?: false}
    assoc =
      %MyAssoc{x: "xyz"}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:sub_assoc, sub_assoc_change)
    changeset =
      %MySchema{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, assoc)
    assert {:error, changeset} = TestRepo.insert(%{changeset | valid?: true})
    refute Map.has_key?(changeset.changes, :id)
    refute Map.has_key?(changeset.changes, :assoc_id)
    refute Map.has_key?(changeset.changes.assoc.changes, :id)
    refute Map.has_key?(changeset.changes.assoc.changes, :sub_assoc_id)
    refute Map.has_key?(changeset.changes.assoc.changes.sub_assoc.changes, :id)
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
    changeset = Ecto.Changeset.change(%MySchema{id: 1, assoc: assoc}, x: "abc")
    schema = TestRepo.update!(changeset)
    assert schema.assoc == assoc
  end

  test "inserting assocs on update" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MySchema{id: 1}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, sample)
    schema = TestRepo.update!(changeset)
    assoc = schema.assoc
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.id == schema.assoc_id
    assert assoc.updated_at
  end

    test "inserting assocs on update preserving parent schema prefix" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MySchema{id: 1}
      |> Ecto.put_meta(prefix: "prefix")
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, sample)
    schema = TestRepo.update!(changeset)
    assoc = schema.assoc
    assert assoc.__meta__.prefix == "prefix"
  end

  test "replacing assocs on update (on_replace: :delete)" do
    sample = %MyAssoc{id: 10, x: "xyz"} |> Ecto.put_meta(state: :loaded)

    # Replacing assoc with a new one
    changeset =
      %MySchema{id: 1, assoc: sample}
      |> Ecto.Changeset.change(x: "1")
      |> Ecto.Changeset.put_assoc(:assoc, %MyAssoc{x: "abc"})
    schema = TestRepo.update!(changeset)
    assoc = schema.assoc
    assert assoc.id != 10
    assert assoc.x == "abc"
    assert assoc.id == schema.assoc_id
    assert assoc.updated_at
    assert_received {:update, _} # Parent
    assert_received {:insert, _} # New assoc
    assert_received {:delete, _} # Old assoc

    # Replacing assoc with nil
    changeset =
      %MySchema{id: 1, assoc: sample}
      |> Ecto.Changeset.change(x: "2")
      |> Ecto.Changeset.put_assoc(:assoc, nil)
    schema = TestRepo.update!(changeset)
    refute schema.assoc
    refute schema.assoc_id
    assert_received {:update, _} # Parent
    refute_received {:insert, _} # New assoc
    assert_received {:delete, _} # Old assoc
  end

  test "replacing assocs on update (on_replace: :nilify)" do
    sample = %MyAssoc{id: 10, x: "xyz"} |> Ecto.put_meta(state: :loaded)

    # Replacing assoc with a new one
    changeset =
      %MySchema{id: 1, nilify_assoc: sample}
      |> Ecto.Changeset.change(x: "1")
      |> Ecto.Changeset.put_assoc(:nilify_assoc, %MyAssoc{x: "abc"})
    schema = TestRepo.update!(changeset)
    assoc = schema.nilify_assoc
    assert assoc.id != 10
    assert assoc.x == "abc"
    assert assoc.id == schema.nilify_assoc_id
    assert assoc.updated_at
    assert_received {:update, _} # Parent
    assert_received {:insert, _} # New assoc
    refute_received {:delete, _} # Old assoc

    # Replacing assoc with nil
    changeset =
      %MySchema{id: 1, nilify_assoc: sample}
      |> Ecto.Changeset.change(x: "2")
      |> Ecto.Changeset.put_assoc(:nilify_assoc, nil)
    schema = TestRepo.update!(changeset)
    refute schema.nilify_assoc
    refute schema.nilify_assoc_id
    assert_received {:update, _} # Parent
    refute_received {:insert, _} # New assoc
    refute_received {:delete, _} # Old assoc
  end

  test "changing assocs on update raises if there is no id" do
    sample = %MyAssoc{x: "xyz"} |> Ecto.put_meta(state: :loaded)
    sample_changeset = Ecto.Changeset.change(sample, x: "abc")

    changeset =
      %MySchema{id: 1, assoc: sample}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, sample_changeset)
    assert_raise Ecto.NoPrimaryKeyValueError, fn ->
      TestRepo.update!(changeset)
    end
  end

  test "changing assocs on update" do
    sample = %MyAssoc{x: "xyz", id: 13, my_schema: 1, sub_assoc: nil}
    sample = put_meta sample, state: :loaded

    # Changing the assoc
    sample_changeset = Ecto.Changeset.change(sample, x: "abc")
    changeset =
      %MySchema{id: 1, assoc: sample}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, sample_changeset)
    schema = TestRepo.update!(changeset)
    assoc = schema.assoc
    assert assoc.id == 13
    assert assoc.x == "abc"
    refute assoc.inserted_at
    assert assoc.updated_at
    refute_received {:delete, _} # Same assoc should not emit delete
  end

  test "removing assocs on update raises if there is no id" do
    assoc = %MyAssoc{x: "xyz"} |> Ecto.put_meta(state: :loaded)

    # Raises if there's no id
    changeset =
      %MySchema{id: 1, assoc: assoc}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, nil)
    assert_raise Ecto.NoPrimaryKeyValueError, fn ->
      TestRepo.update!(changeset)
    end
  end

  test "checks dual changes on update" do
    # values are the same
    changeset =
      %MySchema{id: 1}
      |> Ecto.Changeset.change(assoc_id: 13)
      |> Ecto.Changeset.put_assoc(:assoc, %MyAssoc{x: "xyz", id: 13})
    TestRepo.update!(changeset)

    # values are different
    changeset =
      %MySchema{id: 1}
      |> Ecto.Changeset.change(assoc_id: 13)
      |> Ecto.Changeset.put_assoc(:assoc, %MyAssoc{x: "xyz"})
    assert_raise ArgumentError, ~r"there is already a change setting its foreign key", fn ->
      TestRepo.update!(changeset)
    end
  end

  test "removing assocs on update" do
    assoc = %MyAssoc{x: "xyz", id: 1}

    changeset =
      %MySchema{id: 1, assoc: assoc}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, nil)
    schema = TestRepo.update!(changeset)
    assert schema.assoc == nil
  end

  test "removing assocs on update preserving parent schema prefix" do
    assoc = %MyAssoc{x: "xyz", id: 1} |> Ecto.put_meta(state: :loaded)

    changeset =
      %MySchema{id: 1, assoc: assoc}
      |> Ecto.put_meta(prefix: "prefix")
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, nil)
    TestRepo.update!(changeset)
    assert_received {:delete, %{prefix: "prefix", source: "my_assoc"}}
  end

  test "returns untouched changeset on invalid children on update" do
    assoc = %MyAssoc{x: "xyz"}
    assoc_changeset = %{Ecto.Changeset.change(assoc) | valid?: false}
    changeset =
      %MySchema{id: 1}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, assoc_changeset)
    assert {:error, changeset} = TestRepo.update(%{changeset | valid?: true})
    assert_received {:rollback, ^changeset}
    refute changeset.valid?
  end

  test "returns untouched changeset on constraint mismatch on update" do
    my_schema = %MySchema{id: 1, assoc: nil}
    changeset =
      put_in(my_schema.__meta__.context, {:invalid, [unique: "my_schema_foo_index"]})
      |> Ecto.Changeset.change(x: "foo")
      |> Ecto.Changeset.put_assoc(:assoc, %MyAssoc{x: "xyz"})
      |> Ecto.Changeset.unique_constraint(:foo)
    assert {:error, changeset} = TestRepo.update(changeset)
    assert_received {:rollback, ^changeset}
    refute changeset.data.assoc
    assert changeset.changes.assoc
    refute changeset.changes.assoc.data.id
    refute changeset.valid?
  end

  test "handles valid nested assocs on update" do
    assoc = %MyAssoc{id: 1, x: "xyz"}
    assoc_changeset =
      assoc
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:sub_assoc, %SubAssoc{y: "xyz"})
    changeset =
      %MySchema{id: 1, assoc: assoc}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, assoc_changeset)
    schema = TestRepo.update!(changeset)
    assert schema.assoc.sub_assoc.id

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
      %MySchema{id: 1, assoc: assoc}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, assoc_changeset)

    assert {:error, changeset} = TestRepo.update(%{changeset | valid?: true})
    refute Map.has_key?(changeset.changes.assoc.changes.sub_assoc.changes, :id)
    refute Map.has_key?(changeset.changes.assoc.changes, :sub_assoc_id)
    refute changeset.valid?

    # Just one transaction was used
    assert_received {:transaction, _}
    assert_received {:rollback, ^changeset}
    refute_received {:transaction, _}
    refute_received {:rollback, _}
  end
end
