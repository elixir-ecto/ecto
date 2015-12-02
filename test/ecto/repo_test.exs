defmodule Ecto.RepoTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto.Model, only: [put_meta: 2]
  require Ecto.TestRepo, as: TestRepo

  defmodule SubEmbed do
    use Ecto.Model

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "" do
      field :y, :string
    end

    before_insert :store_changeset, [:before_insert]
    after_insert  :store_changeset, [:after_insert]
    before_update :store_changeset, [:before_update]
    after_update  :store_changeset, [:after_update]
    before_delete :store_changeset, [:before_delete]
    after_delete  :store_changeset, [:after_delete]

    def store_changeset(changeset, stage) do
      Agent.update(CallbackAgent, &[{stage, changeset}|&1])
      changeset
    end
  end

  defmodule MyEmbed do
    use Ecto.Model

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "" do
      field :x, :string
      embeds_one :sub_embed, SubEmbed, on_replace: :delete
      timestamps
    end

    before_insert :store_changeset, [:before_insert]
    after_insert  :store_changeset, [:after_insert]
    before_update :store_changeset, [:before_update]
    after_update  :store_changeset, [:after_update]
    before_delete :store_changeset, [:before_delete]
    after_delete  :store_changeset, [:after_delete]

    def store_changeset(changeset, stage) do
      Agent.update(CallbackAgent, &[{stage, changeset}|&1])
      changeset
    end
  end

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

    before_insert :store_changeset, [:before_insert]
    after_insert  :store_changeset, [:after_insert]
    before_update :store_changeset, [:before_update]
    after_update  :store_changeset, [:after_update]
    before_delete :store_changeset, [:before_delete]
    after_delete  :store_changeset, [:after_delete]

    def store_changeset(changeset, stage) do
      Agent.update(CallbackAgent, &[{stage, changeset}|&1])
      changeset
    end
  end

  defmodule MyModel do
    use Ecto.Model

    schema "my_model" do
      field :x, :string
      field :y, :binary
      embeds_one :embed, MyEmbed, on_replace: :delete
      embeds_many :embeds, MyEmbed, on_replace: :delete
      has_one :assoc, MyAssoc, on_replace: :delete
      has_many :assocs, MyAssoc, on_replace: :delete
    end

    before_insert :store_changeset, [:before_insert]
    after_insert  :store_changeset, [:after_insert]
    before_update :store_changeset, [:before_update]
    after_update  :store_changeset, [:after_update]
    before_delete :store_changeset, [:before_delete]
    after_delete  :store_changeset, [:after_delete]

    def store_changeset(changeset, stage) do
      Agent.update(CallbackAgent, &[{stage, changeset}|&1])
      changeset
    end
  end

  defmodule MyModelNoPK do
    use Ecto.Model

    @primary_key false
    schema "my_model" do
      field :x, :string
    end
  end

  setup do
    {:ok, pid} = Agent.start_link(fn -> [] end, name: CallbackAgent)
    on_exit fn -> Process.alive?(pid) && Agent.stop(pid) end
    :ok
  end

  test "needs model with primary key field" do
    model = %MyModelNoPK{x: "abc"}

    assert_raise Ecto.NoPrimaryKeyFieldError, fn ->
      TestRepo.update!(model |> Ecto.Changeset.change, force: true)
    end

    assert_raise Ecto.NoPrimaryKeyFieldError, fn ->
      TestRepo.delete!(model)
    end

    assert_raise Ecto.NoPrimaryKeyFieldError, fn ->
      TestRepo.get(MyModelNoPK, 123)
    end
  end

  test "works with primary key value" do
    model = %MyModel{id: 1, x: "abc"}
    TestRepo.get(MyModel, 123)
    TestRepo.get_by(MyModel, x: "abc")
    TestRepo.update!(model |> Ecto.Changeset.change, force: true)
    TestRepo.delete!(model)
  end

  test "works with custom source model" do
    model = %MyModel{id: 1, x: "abc"} |> put_meta(source: "custom_model")
    TestRepo.update!(model |> Ecto.Changeset.change, force: true)
    TestRepo.delete!(model)

    to_insert = %MyModel{x: "abc"} |> put_meta(source: "custom_model")
    TestRepo.insert!(to_insert)
  end

  test "fails without primary key value" do
    model = %MyModel{x: "abc"}

    assert_raise Ecto.NoPrimaryKeyValueError, fn ->
      TestRepo.update!(model |> Ecto.Changeset.change, force: true)
    end

    assert_raise Ecto.NoPrimaryKeyValueError, fn ->
      TestRepo.delete!(model)
    end
  end

  test "validates model types" do
    model = %MyModel{x: 123}

    assert_raise Ecto.ChangeError, fn ->
      TestRepo.insert!(model)
    end
  end

  test "validates get" do
    TestRepo.get(MyModel, 123)

    message = "cannot perform Ecto.TestRepo.get/2 because the given value is nil"
    assert_raise ArgumentError, message, fn ->
      TestRepo.get(MyModel, nil)
    end

    message = ~r"value `:atom` in `where` cannot be cast to type :id in query"
    assert_raise Ecto.CastError, message, fn ->
      TestRepo.get(MyModel, :atom)
    end

    message = ~r"expected a from expression with a model in query"
    assert_raise Ecto.QueryError, message, fn ->
      TestRepo.get(%Ecto.Query{}, :atom)
    end
  end

  test "validates get_by" do
    TestRepo.get_by(MyModel, id: 123)

    message = ~r"value `:atom` in `where` cannot be cast to type :id in query"
    assert_raise Ecto.CastError, message, fn ->
      TestRepo.get_by(MyModel, id: :atom)
    end
  end

  test "validates update_all" do
    # Success
    TestRepo.update_all(MyModel, set: [x: "321"])

    query = from(e in MyModel, where: e.x == "123", update: [set: [x: "321"]])
    TestRepo.update_all(query, [])

    # Failures
    assert_raise Ecto.QueryError, fn ->
      TestRepo.update_all from(e in MyModel, select: e), set: [x: "321"]
    end

    assert_raise Ecto.QueryError, fn ->
      TestRepo.update_all from(e in MyModel, order_by: e.x), set: [x: "321"]
    end
  end

  test "validates delete_all" do
    # Success
    TestRepo.delete_all(MyModel)

    query = from(e in MyModel, where: e.x == "123")
    TestRepo.delete_all(query)

    # Failures
    assert_raise Ecto.QueryError, fn ->
      TestRepo.delete_all from(e in MyModel, select: e)
    end

    assert_raise Ecto.QueryError, fn ->
      TestRepo.delete_all from(e in MyModel, order_by: e.x)
    end
  end

  ## Changesets

  test "insert, update, insert_or_update and delete accepts changesets" do
    valid = Ecto.Changeset.cast(%MyModel{id: 1}, %{}, [], [])
    assert {:ok, %MyModel{}} = TestRepo.insert(valid)
    assert {:ok, %MyModel{}} = TestRepo.update(valid)
    assert {:ok, %MyModel{}} = TestRepo.insert_or_update(valid)
    assert {:ok, %MyModel{}} = TestRepo.delete(valid)
  end

  test "insert, update, insert_or_update and delete errors on invalid changeset" do
    invalid = %Ecto.Changeset{valid?: false, model: %MyModel{}}

    insert = %{invalid | action: :insert, repo: TestRepo}
    assert {:error, ^insert} = TestRepo.insert(invalid)

    update = %{invalid | action: :update, repo: TestRepo}
    assert {:error, ^update} = TestRepo.update(invalid)

    update = %{invalid | action: :insert, repo: TestRepo}
    assert {:error, ^update} = TestRepo.insert_or_update(invalid)

    delete = %{invalid | action: :delete, repo: TestRepo}
    assert {:error, ^delete} = TestRepo.delete(invalid)
  end

  test "insert!, update! and delete! accepts changesets" do
    valid = Ecto.Changeset.cast(%MyModel{id: 1}, %{}, [], [])
    assert %MyModel{} = TestRepo.insert!(valid)
    assert %MyModel{} = TestRepo.update!(valid)
    assert %MyModel{} = TestRepo.insert_or_update!(valid)
    assert %MyModel{} = TestRepo.delete!(valid)
  end

  test "insert!, update!, insert_or_update! and delete! fail on invalid changeset" do
    invalid = %Ecto.Changeset{valid?: false, model: %MyModel{}}

    assert_raise Ecto.InvalidChangesetError,
                 ~r"could not perform insert because changeset is invalid", fn ->
      TestRepo.insert!(invalid)
    end

    assert_raise Ecto.InvalidChangesetError,
                 ~r"could not perform update because changeset is invalid", fn ->
      TestRepo.update!(invalid)
    end

    assert_raise Ecto.InvalidChangesetError,
                 ~r"could not perform insert because changeset is invalid", fn ->
      TestRepo.insert_or_update!(invalid)
    end

    assert_raise Ecto.InvalidChangesetError,
                 ~r"could not perform delete because changeset is invalid", fn ->
      TestRepo.delete!(invalid)
    end
  end

  test "insert!, update! and delete! fail on changeset without model" do
    invalid = %Ecto.Changeset{valid?: true, model: nil}

    assert_raise ArgumentError, "cannot insert a changeset without a model", fn ->
      TestRepo.insert!(invalid)
    end

    assert_raise ArgumentError, "cannot update a changeset without a model", fn ->
      TestRepo.update!(invalid)
    end

    assert_raise ArgumentError, "cannot delete a changeset without a model", fn ->
      TestRepo.delete!(invalid)
    end
  end

  test "insert!, update!, insert_or_update! and delete! fail on changeset with wrong action" do
    invalid = %Ecto.Changeset{valid?: true, model: %MyModel{}, action: :other}

    assert_raise ArgumentError, "a changeset with action :other was given to Ecto.TestRepo.insert/2", fn ->
      TestRepo.insert!(invalid)
    end

    assert_raise ArgumentError, "a changeset with action :other was given to Ecto.TestRepo.update/2", fn ->
      TestRepo.update!(invalid)
    end

    assert_raise ArgumentError, "a changeset with action :other was given to Ecto.TestRepo.insert/2", fn ->
      TestRepo.insert_or_update!(invalid)
    end

    assert_raise ArgumentError, "a changeset with action :other was given to Ecto.TestRepo.delete/2", fn ->
      TestRepo.delete!(invalid)
    end
  end

  test "insert_or_update uses the correct method" do
    built  = Ecto.Changeset.cast(%MyModel{y: "built"}, %{}, [], [])
    loaded =
      %MyModel{y: "loaded"}
      |> TestRepo.insert!
      |> Ecto.Changeset.cast(%{y: "updated"}, [:y], [])
    assert_received :insert

    TestRepo.insert_or_update built
    assert_received :insert

    TestRepo.insert_or_update loaded
    assert_received :update
  end

  test "insert_or_update fails on invalid states" do
    deleted =
      %MyModel{y: "deleted"}
      |> TestRepo.insert!
      |> TestRepo.delete!
      |> Ecto.Changeset.cast(%{y: "updated"}, [:y], [])

    assert_raise ArgumentError, ~r/the changeset has an invalid state/, fn ->
      TestRepo.insert_or_update deleted
    end
  end

  test "insert_or_update fails when being passed a struct" do
    assert_raise ArgumentError, ~r/giving a struct to .* is not supported/, fn ->
      TestRepo.insert_or_update %MyModel{}
    end
  end

  ## Changesets

  @uuid "30313233-3435-3637-3839-616263646566"

  test "uses correct status" do
    get_action = fn [{stage, changeset}|_] ->
      {stage, changeset.action}
    end

    TestRepo.insert!(%MyModel{})
    assert Agent.get(CallbackAgent, get_action) == {:after_insert, :insert}

    changeset = Ecto.Changeset.cast(%MyModel{}, %{}, [], [])
    TestRepo.insert!(changeset)
    assert Agent.get(CallbackAgent, get_action) == {:after_insert, :insert}

    changeset = Ecto.Changeset.cast(%MyModel{id: 1}, %{}, [], [])
    TestRepo.update!(changeset, force: true)
    assert Agent.get(CallbackAgent, get_action) == {:after_update, :update}

    TestRepo.delete!(%MyModel{id: 1})
    assert Agent.get(CallbackAgent, get_action) == {:after_delete, :delete}

    changeset = Ecto.Changeset.cast(%MyModel{id: 1}, %{}, [], [])
    TestRepo.delete!(changeset)
    assert Agent.get(CallbackAgent, get_action) == {:after_delete, :delete}
  end

  defp get_before_changes([_, {_, changeset} | _]), do: changeset.changes
  defp get_after_changes([{_, changeset} | _]), do: changeset.changes

  test "skips adding assocs to changeset on insert" do
    TestRepo.insert!(%MyModel{})
    assert Agent.get(CallbackAgent, &get_before_changes/1) ==
      %{id: nil, embed: nil, embeds: [], x: nil, y: nil}
    assert Agent.get(CallbackAgent, &get_after_changes/1) ==
      %{id: nil, x: nil, y: nil}
  end

  defp get_models(changesets) do
    Enum.map(changesets, fn {stage, changeset} ->
      {stage, changeset.model.__struct__}
    end)
  end

  test "handles assocs on insert when ok" do
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

  test "handles assocs on insert when error" do
    assoc = %MyAssoc{x: "xyz"}
    assoc_changeset = Ecto.Changeset.change(assoc)

    # Raises with assocs when inserting model
    assert_raise ArgumentError, ~r"set for assoc named `assoc`", fn ->
      TestRepo.insert!(%MyModel{assoc: assoc})
    end

    assert_raise ArgumentError, ~r"set for assoc named `assocs`", fn ->
      TestRepo.insert!(%MyModel{assocs: [assoc]})
    end

    # Raises if action is delete
    changeset = Ecto.Changeset.change(%MyModel{}, assoc: assoc_changeset)
    changeset = put_in(changeset.changes.assoc.action, :delete)
    assert_raise ArgumentError, ~r"got action :delete in changeset for associated .* while inserting", fn ->
      TestRepo.insert!(changeset)
    end

    # Returns error and rollbacks on invalid children
    assoc_changeset = %{Ecto.Changeset.change(assoc) | valid?: false}
    changeset = Ecto.Changeset.change(%MyModel{}, assoc: assoc_changeset)
    assert {:error, changeset} = TestRepo.insert(changeset)
    assert_received {:rollback, ^changeset}
    refute changeset.valid?

    # Returns error and rollbacks on invalid constraint
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

  test "fails cleanly for bad assocs on insert" do
    assoc = Ecto.Changeset.change(%MyAssoc{})
            |> Ecto.Changeset.put_change(:x, "xyz")
            |> Ecto.Changeset.put_change(:my_model, %MyModel{})

    assert_raise ArgumentError, ~r/cannot insert `my_model` in Ecto.RepoTest.MyAssoc/, fn ->
      TestRepo.insert!(assoc)
    end
  end

  test "handles assocs on insert with assoc constraint error" do
    assoc_changeset =
      put_in(%MyAssoc{}.__meta__.context, {:invalid, [unique: "my_assoc_foo_index"]})
      |> Ecto.Changeset.change
      |> Ecto.Changeset.unique_constraint(:foo)

    changeset = Ecto.Changeset.change(%MyModel{}, assoc: assoc_changeset)
    assert {:error, changeset} = TestRepo.insert(changeset)
    assert changeset.model.__meta__.state == :built
    assert changeset.changes.assoc
    refute changeset.valid?

    # Just one transaction was used
    assert_received {:transaction, _}
    assert_received {:rollback, ^changeset}
    refute_received {:transaction, _}
    refute_received {:rollback, _}
  end

  test "handles nested assocs on insert" do
    sub_assoc = %SubAssoc{y: "xyz"}
    inserted_assoc = put_in sub_assoc.__meta__.state, :loaded

    assoc = Ecto.Changeset.change(%MyAssoc{x: "xyz"}, sub_assoc: sub_assoc)
    changeset = Ecto.Changeset.change(%MyModel{}, assoc: assoc)
    model = TestRepo.insert!(changeset)
    id = model.assoc.sub_assoc.id
    assert id
    assert model.assoc.sub_assoc == %{inserted_assoc | id: id, my_assoc_id: model.assoc.id}

    # Just one transaction was used
    assert_received {:transaction, _}
    refute_received {:rollback, _}

    sub_assoc_change = %{Ecto.Changeset.change(sub_assoc) | valid?: false}
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
    assert [{:after_update, MyModel}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.assoc == assoc

    changeset = Ecto.Changeset.change(%MyModel{id: 1, assocs: [assoc]}, x: "abc")
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.assocs == [assoc]
  end

  test "inserting assocs on update" do
    sample = %MyAssoc{x: "xyz"}

    # Inserting the assoc
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


  test "changing assocs on update" do
    sample = %MyAssoc{x: "xyz"}
    sample_changeset = Ecto.Changeset.change(sample, x: "abc")

    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: sample}, assoc: sample_changeset)
    assert_raise Ecto.NoPrimaryKeyValueError, fn ->
      TestRepo.update!(changeset)
    end

    sample = %MyAssoc{x: "xyz", id: 13, my_model: 1, sub_assoc: nil}
    sample = put_in sample.__meta__.state, :loaded

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

    # With no changes
    no_changes = Ecto.Changeset.change(sample)
    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: sample},
                                      assoc: no_changes, x: "abc")
    model = TestRepo.update!(changeset)
    refute model.assoc.updated_at
  end

  test "removing assocs on update" do
    assoc = %MyAssoc{x: "xyz"}

    # Raises if there's no id
    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: assoc}, assoc: nil)
    assert_raise Ecto.NoPrimaryKeyValueError, fn ->
      TestRepo.update!(changeset)
    end

    assoc = %{assoc | id: 1}

    # Deleting the assoc
    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: assoc}, assoc: nil)
    model = TestRepo.update!(changeset)
    assert model.assoc == nil

    changeset = Ecto.Changeset.change(%MyModel{id: 1, assocs: [assoc]}, assocs: [])
    model = TestRepo.update!(changeset)
    assert model.assocs == []
  end


  test "handles assocs on update when error" do
    assoc = %MyAssoc{x: "xyz"}

    # Returns error and rollbacks on invalid children
    assoc_changeset = %{Ecto.Changeset.change(assoc) | valid?: false}
    changeset = Ecto.Changeset.change(%MyModel{id: 1}, assoc: assoc_changeset)
    assert {:error, changeset} = TestRepo.update(changeset)
    assert_received {:rollback, ^changeset}
    refute changeset.valid?

    # Returns error and rollbacks on invalid constraint
    assoc_changeset = Ecto.Changeset.change(assoc)
    my_model = %MyModel{id: 1, assoc: nil}
    changeset =
      put_in(my_model.__meta__.context, {:invalid, [unique: "my_model_foo_index"]})
      |> Ecto.Changeset.change(assoc: assoc_changeset, x: "foo")
      |> Ecto.Changeset.unique_constraint(:foo)
    assert {:error, changeset} = TestRepo.update(changeset)
    assert_received {:rollback, ^changeset}
    assert changeset.changes.assoc
    refute changeset.valid?
  end

  test "handles nested assocs on update" do
    sub_assoc = %SubAssoc{y: "xyz"}
    inserted_assoc = put_in sub_assoc.__meta__.state, :loaded

    assoc = %MyAssoc{id: 1, x: "xyz"}
    assoc_changeset = Ecto.Changeset.change(assoc, sub_assoc: sub_assoc)
    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: assoc}, assoc: assoc_changeset)
    model = TestRepo.update!(changeset)
    id = model.assoc.sub_assoc.id
    assert model.assoc.sub_assoc == %{inserted_assoc | id: id, my_assoc_id: model.assoc.id}

    # One transaction was used
    assert_received {:transaction, _}
    refute_received {:rollback, _}

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
