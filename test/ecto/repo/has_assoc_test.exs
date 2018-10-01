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
      belongs_to :my_schema, MySchema
      timestamps()
    end

    def changeset(struct, params) do
      if params[:delete] do
        %{Ecto.Changeset.cast(struct, params, []) | action: :delete}
      else
        Ecto.Changeset.cast(struct, params, [])
      end
    end
  end

  defmodule MySchema do
    use Ecto.Schema

    schema "my_schema" do
      field :x, :string
      field :y, :binary
      has_one :assoc, MyAssoc, on_replace: :delete
      has_one :nilify_assoc, MyAssoc, on_replace: :nilify
      has_one :delete_assoc, MyAssoc
      has_many :assocs, MyAssoc, on_replace: :delete
      has_many :delete_assocs, MyAssoc
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
    assert assoc.my_schema_id == schema.id
    assert assoc.inserted_at

    changeset =
      %MySchema{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [sample])
    schema = TestRepo.insert!(changeset)
    [assoc] = schema.assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.my_schema_id == schema.id
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

    changeset =
      %MySchema{}
      |> Ecto.put_meta(prefix: "prefix")
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [sample])
    schema = TestRepo.insert!(changeset)
    [assoc] = schema.assocs

    assert assoc.__meta__.prefix == "prefix"
  end

  test "handles assocs from struct on insert" do
    schema = TestRepo.insert!(%MySchema{assoc: %MyAssoc{x: "xyz"}})
    assoc = schema.assoc
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.my_schema_id == schema.id
    assert assoc.inserted_at

    schema = TestRepo.insert!(%MySchema{assocs: [%MyAssoc{x: "xyz"}]})
    [assoc] = schema.assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.my_schema_id == schema.id
    assert assoc.inserted_at
  end

  test "handles invalid assocs from struct on insert" do
    {:error, changeset} = TestRepo.insert(%MySchema{assoc: 1})
    assert changeset.errors == [assoc: {"is invalid", type: :map}]
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
    assert schema.__meta__.prefix == "prefix"
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
    refute changeset.changes.assoc.changes.my_schema_id
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

  test "duplicate pk on insert" do
    assocs = [%MyAssoc{x: "xyz", id: 1} |> Ecto.Changeset.change,
              %MyAssoc{x: "abc", id: 1} |> Ecto.Changeset.change]
    changeset =
      %MySchema{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, assocs)
    assert {:error, changeset} = TestRepo.insert(changeset)
    refute changeset.valid?
    errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    assert errors == %{assocs: [%{}, %{id: ["has already been taken"]}]}
  end

  test "skips assocs on update when not changing" do
    assoc = %MyAssoc{x: "xyz"}

    # If assoc is not in changeset, assocs are left out
    changeset = Ecto.Changeset.change(%MySchema{id: 1, assoc: assoc}, x: "abc")
    schema = TestRepo.update!(changeset)
    assert schema.assoc == assoc

    changeset = Ecto.Changeset.change(%MySchema{id: 1, assocs: [assoc]}, x: "abc")
    schema = TestRepo.update!(changeset)
    assert schema.assocs == [assoc]
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
    assert assoc.my_schema_id == schema.id
    assert assoc.updated_at

    changeset =
      %MySchema{id: 1}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [sample])
    schema = TestRepo.update!(changeset)
    [assoc] = schema.assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.my_schema_id == schema.id
    assert assoc.updated_at
  end

  test "inserting assocs on update preserving schema prefix" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MySchema{id: 1}
      |> Ecto.put_meta(prefix: "prefix")
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, sample)
    schema = TestRepo.update!(changeset)
    assoc = schema.assoc
    assert assoc.__meta__.prefix == "prefix"

    changeset =
      %MySchema{id: 1}
      |> Ecto.put_meta(prefix: "prefix")
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [sample])
    schema = TestRepo.update!(changeset)
    [assoc] = schema.assocs
    assert assoc.__meta__.prefix == "prefix"
  end

  test "updating assoc with action: :delete" do
    sample = %MyAssoc{id: 10, x: "xyz"} |> Ecto.put_meta(state: :loaded)

    changeset =
      %MySchema{id: 1, delete_assoc: sample}
      |> Ecto.Changeset.cast(%{x: "abc", delete_assoc: %{delete: true, id: 10}}, [:x])
      |> Ecto.Changeset.cast_assoc(:delete_assoc)
    schema = TestRepo.update!(changeset)
    refute schema.delete_assoc
    assert_received {:update, _} # Parent
    assert_received {:delete, _} # Old assoc
  end

  test "updating assocs with action: :delete" do
    sample = %MyAssoc{id: 10, x: "xyz"} |> Ecto.put_meta(state: :loaded)

    changeset =
      %MySchema{id: 1, delete_assocs: [sample]}
      |> Ecto.Changeset.cast(%{x: "abc", delete_assocs: [%{delete: true, id: 10}]}, [:x])
      |> Ecto.Changeset.cast_assoc(:delete_assocs)
    schema = TestRepo.update!(changeset)
    assert schema.delete_assocs == []
    assert_received {:update, _} # Parent
    assert_received {:delete, _} # Old assoc
  end

  test "replacing assocs on update on_replace: :delete" do
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
    assert assoc.my_schema_id == schema.id
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
    assert_received {:update, _} # Parent
    refute_received {:insert, _} # New assoc
    assert_received {:delete, _} # Old assoc
  end

  test "replacing assocs on update on_replace: :nilify" do
    sample = %MyAssoc{id: 10, my_schema_id: 1, x: "xyz"} |> Ecto.put_meta(state: :loaded)

    # Replacing assoc with a new one
    changeset =
      %MySchema{id: 1, nilify_assoc: sample}
      |> Ecto.Changeset.change(x: "1")
      |> Ecto.Changeset.put_assoc(:nilify_assoc, %MyAssoc{x: "abc"})
    schema = TestRepo.update!(changeset)
    assoc = schema.nilify_assoc
    assert assoc.id != 10
    assert assoc.x == "abc"
    assert assoc.my_schema_id == schema.id
    assert assoc.updated_at
    assert_received {:update, _} # Parent
    assert_received {:insert, _} # New assoc
    assert_received {:update, _} # Old assoc

    # Replacing assoc with nil
    changeset =
      %MySchema{id: 1, nilify_assoc: sample}
      |> Ecto.Changeset.change(x: "2")
      |> Ecto.Changeset.put_assoc(:nilify_assoc, nil)
    schema = TestRepo.update!(changeset)
    refute schema.nilify_assoc
    assert_received {:update, _} # Parent
    refute_received {:insert, _} # New assoc
    assert_received {:update, _} # Old assoc
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

    changeset =
      %MySchema{id: 1, assocs: [sample]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [sample_changeset])
    schema = TestRepo.update!(changeset)
    [assoc] = schema.assocs
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

  test "removing assocs on update" do
    assoc = %MyAssoc{x: "xyz", id: 1}

    changeset =
      %MySchema{id: 1, assoc: assoc}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, nil)
    schema = TestRepo.update!(changeset)
    assert schema.assoc == nil

    changeset =
      %MySchema{id: 1, assocs: [assoc]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [])
    schema = TestRepo.update!(changeset)
    assert schema.assocs == []
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

    changeset =
      %MySchema{id: 1, assocs: [assoc]}
      |> Ecto.put_meta(prefix: "prefix")
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [])
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
    refute Map.has_key?(changeset.changes.assoc.changes.sub_assoc.changes, :my_assoc_id)
    refute changeset.valid?

    # Just one transaction was used
    assert_received {:transaction, _}
    assert_received {:rollback, ^changeset}
    refute_received {:transaction, _}
    refute_received {:rollback, _}
  end
end
