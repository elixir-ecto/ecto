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
      timestamps()
    end
  end

  defmodule MySchemaAssoc do
    use Ecto.Schema

    schema "schemas_assocs" do
      field :public, :boolean, default: false
      belongs_to :my_schema, MySchema
      belongs_to :my_assoc, MyAssoc
      timestamps()
    end
  end

  defmodule MySchemaPrefixAssoc do
    use Ecto.Schema

    @schema_prefix "schema_assoc_prefix"
    schema "schemas_prefix_assocs" do
      field :public, :boolean, default: false
      belongs_to :my_schema, MySchema
      belongs_to :my_assoc, MyAssoc
      timestamps()
    end
  end

  defmodule MySchema do
    use Ecto.Schema

    schema "my_schema" do
      field :x, :string
      field :y, :binary
      many_to_many :assocs, MyAssoc, join_through: "schemas_assocs", on_replace: :delete
      many_to_many :where_assocs, MyAssoc, join_through: "schemas_assocs", join_where: [public: true], on_replace: :delete
      many_to_many :schema_assocs, MyAssoc, join_through: MySchemaAssoc, join_defaults: [public: true]
      many_to_many :schema_prefix_assocs, MyAssoc, join_through: MySchemaPrefixAssoc, join_defaults: [public: true]
      many_to_many :mfa_schema_assocs, MyAssoc, join_through: MySchemaAssoc, join_defaults: {__MODULE__, :send_to_self, [:extra]}
    end

    def send_to_self(struct, owner, extra) do
      send(self(), {:defaults, struct, owner, extra})
      %{struct | public: true}
    end
  end

  test "handles assocs on insert" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MySchema{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [sample])
    schema = TestRepo.insert!(changeset)
    [assoc] = schema.assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.inserted_at
    assert_received {:insert, _}
    assert_received {:insert_all, %{source: "schemas_assocs"}, [[my_assoc_id: 1, my_schema_id: 1]]}
  end

  test "handles assocs on insert preserving parent schema prefix" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MySchema{}
      |> Ecto.put_meta(prefix: "prefix")
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [sample])

    schema = TestRepo.insert!(changeset)
    [assoc] = schema.assocs
    assert assoc.__meta__.prefix == "prefix"
    assert_received {:insert_all, %{source: "schemas_assocs", prefix: "prefix"}, [[my_assoc_id: 1, my_schema_id: 1]]}
  end

  test "handles assocs on insert with schema and keyword defaults" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MySchema{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:schema_assocs, [sample])

    schema = TestRepo.insert!(changeset)
    [assoc] = schema.schema_assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.inserted_at
    assert_received {:insert, _child}
    assert_received {:insert, _parent}
    assert_received {:insert, join}

    # Available from defaults
    assert join.fields[:my_schema_id] == schema.id
    assert join.fields[:my_assoc_id] == assoc.id
    assert join.fields[:public]
  end

  test "handles assocs on insert with schema and MFA defaults" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MySchema{x: "abc"}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:mfa_schema_assocs, [sample])

    schema = TestRepo.insert!(changeset)
    [assoc] = schema.mfa_schema_assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.inserted_at
    assert_received {:insert, _child}
    assert_received {:insert, _parent}
    assert_received {:insert, join}

    # Available from defaults
    assert join.fields[:my_schema_id] == schema.id
    assert join.fields[:my_assoc_id] == assoc.id
    assert join.fields[:public]

    assert_received {:defaults, %MySchemaAssoc{}, %MySchema{x: "abc"}, :extra}
  end

  test "handles assocs on insert with schema preserving parent schema prefix" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MySchema{}
      |> Ecto.put_meta(prefix: "prefix")
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:schema_assocs, [sample])

    schema = TestRepo.insert!(changeset)
    [assoc] = schema.schema_assocs
    assert assoc.__meta__.prefix == "prefix"
    assert_received {:insert, %{source: "schemas_assocs", prefix: "prefix"}}
  end

  test "handles assocs on insert with schema preserving join table schema prefix" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MySchema{}
      |> Ecto.put_meta(prefix: "prefix")
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:schema_prefix_assocs, [sample])

    schema = TestRepo.insert!(changeset)
    [assoc] = schema.schema_prefix_assocs
    assert assoc.__meta__.prefix == "prefix"
    assert_received {:insert, %{source: "schemas_prefix_assocs", prefix: "schema_assoc_prefix"}}
  end

  test "handles assocs from struct on insert" do
    schema = TestRepo.insert!(%MySchema{assocs: [%MyAssoc{x: "xyz"}]})
    [assoc] = schema.assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.inserted_at
    assert_received {:insert, _}
    assert_received {:insert_all, %{source: "schemas_assocs"}, [[my_assoc_id: 1, my_schema_id: 1]]}
  end

  test "handles assocs from struct on insert preserving parent schema prefix" do
    sample = %MyAssoc{x: "xyz"}

    schema = %MySchema{assocs: [sample]} |> Ecto.put_meta(prefix: "prefix")
    schema = TestRepo.insert!(schema)
    [assoc] = schema.assocs
    assert assoc.__meta__.prefix == "prefix"
    assert_received {:insert_all, %{source: "schemas_assocs", prefix: "prefix"}, [[my_assoc_id: 1, my_schema_id: 1]]}
  end

  test "handles invalid assocs from struct on insert" do
    {:error, changeset} = TestRepo.insert(%MySchema{assocs: [1]})
    assert changeset.errors == [assocs: {"is invalid", type: {:array, :map}}]
  end

  test "raises on action mismatch on insert" do
    assoc = %{Ecto.Changeset.change(%MyAssoc{x: "xyz"}) | action: :delete}

    changeset =
      %MySchema{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [assoc])

    assert_raise ArgumentError, ~r"got action :delete in changeset for associated .* while inserting", fn ->
      TestRepo.insert!(changeset)
    end
  end

  test "returns untouched changeset on invalid children on insert" do
    assoc = %{Ecto.Changeset.change(%MyAssoc{x: "xyz"}) | valid?: false}

    changeset =
      %MySchema{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [assoc])

    assert {:error, changeset} = TestRepo.insert(%{changeset | valid?: true})
    assert_received {:rollback, ^changeset}
    refute changeset.valid?
  end

  test "returns untouched changeset on parent constraint mismatch on insert" do
    assoc = Ecto.Changeset.change(%MyAssoc{x: "xyz"})

    changeset =
      put_in(%MySchema{}.__meta__.context, {:invalid, [unique: "my_schema_foo_index"]})
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [assoc])
      |> Ecto.Changeset.unique_constraint(:foo)
    assert {:error, changeset} = TestRepo.insert(changeset)
    assert_received {:rollback, ^changeset}
    assert changeset.data.__meta__.state == :built
    assert %Ecto.Association.NotLoaded{} = changeset.data.assocs
    assert changeset.changes.assocs
    refute hd(changeset.changes.assocs).data.id
    refute changeset.valid?
  end

  test "returns untouched changeset on child constraint mismatch on insert" do
    assoc =
      put_in(%MyAssoc{}.__meta__.context, {:invalid, [unique: "my_assoc_foo_index"]})
      |> Ecto.Changeset.change
      |> Ecto.Changeset.unique_constraint(:foo)

    changeset =
      %MySchema{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [assoc])
    assert {:error, changeset} = TestRepo.insert(changeset)
    assert changeset.data.__meta__.state == :built
    assert %Ecto.Association.NotLoaded{} = changeset.data.assocs
    assert changeset.changes.assocs
    refute hd(changeset.changes.assocs).data.id
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
      %MySchema{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [assoc])
    schema = TestRepo.insert!(changeset)
    assert hd(schema.assocs).sub_assoc.id

    # Just one transaction was used
    assert_received {:transaction, _}
    refute_received {:rollback, _}
    assert_received {:insert_all, %{source: "schemas_assocs"}, [[my_assoc_id: 1, my_schema_id: 1]]}
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
      |> Ecto.Changeset.put_assoc(:assocs, [assoc])
    schema = TestRepo.insert!(changeset)
    assert hd(schema.assocs).sub_assoc.__meta__.prefix == "prefix"
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
    changeset = Ecto.Changeset.change(%MySchema{id: 1, assocs: [assoc]}, x: "abc")
    schema = TestRepo.update!(changeset)
    assert schema.assocs == [assoc]
  end

  test "inserting assocs on update" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MySchema{id: 3}
      |> Ecto.Changeset.change(x: "1")
      |> Ecto.Changeset.put_assoc(:assocs, [sample])
    schema = TestRepo.update!(changeset)
    [assoc] = schema.assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.updated_at
    assert_received {:update, _}
    assert_received {:insert_all, %{source: "schemas_assocs"}, [[my_assoc_id: 1, my_schema_id: 3]]}
  end

  test "inserting assocs on update preserving parent schema prefix" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MySchema{id: 3}
      |> Ecto.put_meta(prefix: "prefix")
      |> Ecto.Changeset.change(x: "1")
      |> Ecto.Changeset.put_assoc(:assocs, [sample])
    schema = TestRepo.update!(changeset)
    [assoc] = schema.assocs
    assert assoc.__meta__.prefix == "prefix"
    assert_received {:insert_all, %{source: "schemas_assocs", prefix: "prefix"}, [[my_assoc_id: 1, my_schema_id: 3]]}
  end

  test "inserting assocs on update with schema" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MySchema{id: 3}
      |> Ecto.Changeset.change(x: "1")
      |> Ecto.Changeset.put_assoc(:schema_assocs, [sample])
    schema = TestRepo.update!(changeset)
    [assoc] = schema.schema_assocs
    assert assoc.id
    assert assoc.x == "xyz"
    assert assoc.updated_at
    assert_received {:update, _}
    assert_received {:insert, _}
  end

  test "inserting assocs on update with schema preserving parent schema prefix" do
    sample = %MyAssoc{x: "xyz"}

    changeset =
      %MySchema{id: 3}
      |> Ecto.put_meta(prefix: "prefix")
      |> Ecto.Changeset.change(x: "1")
      |> Ecto.Changeset.put_assoc(:schema_assocs, [sample])
    schema = TestRepo.update!(changeset)
    [assoc] = schema.schema_assocs
    assert assoc.__meta__.prefix == "prefix"
    assert_received {:insert, %{source: "schemas_assocs", prefix: "prefix"}}
  end

  test "replacing assocs on update on_replace" do
    sample = %MyAssoc{id: 10, x: "xyz"} |> Ecto.put_meta(state: :loaded)

    # Replacing assoc with a new one
    changeset =
      %MySchema{id: 3, assocs: [sample]}
      |> Ecto.Changeset.change(x: "1")
      |> Ecto.Changeset.put_assoc(:assocs, [%MyAssoc{x: "abc"}])
    schema = TestRepo.update!(changeset)
    [assoc] = schema.assocs
    assert assoc.id != 10
    assert assoc.x == "abc"
    assert assoc.updated_at
    assert_received {:update, _} # Parent
    assert_received {:insert, _} # New assoc
    refute_received {:delete, _} # Old assoc
    assert_received {:insert_all, %{source: "schemas_assocs"}, [[my_assoc_id: 1, my_schema_id: 3]]}
    assert_received {:delete_all, %{from: %{source: {"schemas_assocs", _}}}}

    # Replacing assoc with nil
    changeset =
      %MySchema{id: 1, assocs: [sample]}
      |> Ecto.Changeset.change(x: "2")
      |> Ecto.Changeset.put_assoc(:assocs, [])
    schema = TestRepo.update!(changeset)
    assert schema.assocs == []
    assert_received {:update, _} # Parent
    refute_received {:insert, _} # New assoc
    refute_received {:delete, _} # Old assoc
    refute_received {:insert_all, _, _}
    assert_received {:delete_all, _}
  end

  test "deleting assocs with join_where on update on_replace" do
    sample = %MyAssoc{id: 10, x: "xyz"} |> Ecto.put_meta(state: :loaded)

    changeset =
      %MySchema{id: 3, assocs: [sample], where_assocs: [sample]} |> Ecto.Changeset.change()

    # removing assoc with == join_where
    changeset |> Ecto.Changeset.put_assoc(:where_assocs, []) |> TestRepo.update!()

    assert_received {:delete_all, query}
    assert inspect(query) =~ "where: s0.my_schema_id == ^..., where: s0.my_assoc_id == ^... and s0.public == ^..."

    # removing assoc without join_where
    changeset |> Ecto.Changeset.put_assoc(:assocs, []) |> TestRepo.update!()

    assert_received {:delete_all, query}
    assert inspect(query) =~ "where: s0.my_schema_id == ^..., where: s0.my_assoc_id == ^..."
    refute inspect(query) =~ "s0.public == ^..."
  end

  test "changing assocs on update raises if there is no id" do
    sample = %MyAssoc{x: "xyz"} |> Ecto.put_meta(state: :loaded)
    sample_changeset = Ecto.Changeset.change(sample, x: "abc")

    changeset =
      %MySchema{id: 1, assocs: [sample]}
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
      %MySchema{id: 1, assocs: [sample]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [sample_changeset])
    schema = TestRepo.update!(changeset)
    [assoc] = schema.assocs
    assert assoc.id == 13
    assert assoc.x == "abc"
    refute assoc.inserted_at
    assert assoc.updated_at
    refute_received :delete # Same assoc should not emit delete
    refute_received {:delete_all, _}
    refute_received {:insert_all, _, _}
  end

  test "adding struct assocs on update" do
    sample = %MyAssoc{x: "xyz", id: 13, sub_assoc: nil}
    sample = put_meta sample, state: :loaded
    latest = %MyAssoc{x: "abc", id: 11, sub_assoc: nil}

    # Changing the assoc
    changeset =
      %MySchema{id: 1, assocs: [sample]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [sample, latest])
    schema = TestRepo.update!(changeset)
    [sample, latest] = schema.assocs

    assert sample.id == 13
    assert sample.x == "xyz"
    refute sample.inserted_at
    refute sample.updated_at

    assert latest.id == 11
    assert latest.x == "abc"
    assert latest.inserted_at
    assert latest.updated_at
  end

  test "adding mixed changeset and struct assocs on update" do
    sample = %MyAssoc{x: "xyz", id: 13, sub_assoc: nil}
    sample = put_meta sample, state: :loaded
    sample = Ecto.Changeset.change(sample, x: "XYZ")
    latest = %MyAssoc{x: "abc", id: 11, sub_assoc: nil}

    # Changing the assoc
    changeset =
      %MySchema{id: 1, assocs: [sample]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [sample, latest])
    schema = TestRepo.update!(changeset)
    [sample, latest] = schema.assocs

    assert sample.id == 13
    assert sample.x == "XYZ"
    refute sample.inserted_at
    assert sample.updated_at

    assert latest.id == 11
    assert latest.x == "abc"
    assert latest.inserted_at
    assert latest.updated_at
  end

  test "removing assocs on update raises if there is no id" do
    assoc = %MyAssoc{x: "xyz"} |> Ecto.put_meta(state: :loaded)

    # Raises if there's no id
    changeset =
      %MySchema{id: 1, assocs: [assoc]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [])
    assert_raise RuntimeError,  ~r/could not delete join entry because `id` is nil/, fn ->
      TestRepo.update!(changeset)
    end
  end

  test "removing assocs on update" do
    assoc = %MyAssoc{x: "xyz", id: 1}

    changeset =
      %MySchema{id: 1, assocs: [assoc]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [])
    schema = TestRepo.update!(changeset)
    assert schema.assocs == []
    assert_received {:delete_all, %{prefix: nil, from: %{source: {"schemas_assocs", _}}}}
  end

  test "removing assocs on update preserving parent schema prefix" do
    assoc = %MyAssoc{x: "xyz", id: 1}

    changeset =
      %MySchema{id: 1, assocs: [assoc]}
      |> Ecto.put_meta(prefix: "prefix")
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [])
    TestRepo.update!(changeset)
    assert_received {:delete_all, %{prefix: "prefix", from: %{source: {"schemas_assocs", _}}}}
  end

  test "returns untouched changeset on invalid children on update" do
    assoc = %MyAssoc{x: "xyz"}
    assoc_changeset = %{Ecto.Changeset.change(assoc) | valid?: false}
    changeset =
      %MySchema{id: 1}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [assoc_changeset])
    assert {:error, changeset} = TestRepo.update(%{changeset | valid?: true})
    assert_received {:rollback, ^changeset}
    refute changeset.valid?
  end

  test "returns untouched changeset on constraint mismatch on update" do
    my_schema = %MySchema{id: 1, assocs: []}

    changeset =
      put_in(my_schema.__meta__.context, {:invalid, [unique: "my_schema_foo_index"]})
      |> Ecto.Changeset.change(x: "foo")
      |> Ecto.Changeset.put_assoc(:assocs, [%MyAssoc{x: "xyz"}])
      |> Ecto.Changeset.unique_constraint(:foo)
    assert {:error, changeset} = TestRepo.update(changeset)
    assert_received {:rollback, ^changeset}
    assert changeset.data.assocs == []
    refute changeset.valid?

    [assoc] = changeset.changes.assocs
    refute assoc.data.id
  end

  test "handles valid nested assocs on update" do
    assoc = %MyAssoc{id: 1, x: "xyz"}
    assoc_changeset =
      assoc
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:sub_assoc, %SubAssoc{y: "xyz"})
    changeset =
      %MySchema{id: 1, assocs: [assoc]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assocs, [assoc_changeset])
    schema = TestRepo.update!(changeset)
    assert hd(schema.assocs).sub_assoc.id

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
      %MySchema{id: 1, assocs: [assoc]}
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
