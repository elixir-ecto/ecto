defmodule Ecto.RepoTest do
  use ExUnit.Case, async: true

  import Ecto.Query
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
    model = %MyModel{id: 1, x: "abc"} |> Ecto.Model.put_meta(source: "custom_model")
    TestRepo.update!(model |> Ecto.Changeset.change, force: true)
    TestRepo.delete!(model)

    to_insert = %MyModel{x: "abc"} |> Ecto.Model.put_meta(source: "custom_model")
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

    message = "cannot perform Ecto.TestRepo.get_by/2 because :id is nil"
    assert_raise ArgumentError, message, fn ->
      TestRepo.get_by(MyModel, id: nil)
    end

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

    changeset = Ecto.Changeset.change(%MyEmbed{})
    assert catch_error(TestRepo.update_all MyModel, set: [embed: %MyEmbed{}])
    assert catch_error(TestRepo.update_all MyModel, set: [embed: changeset])
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

    insert = %{invalid | action: :insert, repo: TestRepo, opts: [source: :changeset]}
    assert {:error, ^insert} = TestRepo.insert(invalid)

    update = %{invalid | action: :update, repo: TestRepo, opts: [source: :changeset]}
    assert {:error, ^update} = TestRepo.update(invalid)

    update = %{invalid | action: :insert, repo: TestRepo, opts: [source: :changeset]}
    assert {:error, ^update} = TestRepo.insert_or_update(invalid)

    delete = %{invalid | action: :delete, repo: TestRepo, opts: [source: :changeset]}
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

  test "uses the correct method for insert_or_update" do
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

  test "fails on invalid states" do
    deleted =
      %MyModel{y: "deleted"}
      |> TestRepo.insert!
      |> TestRepo.delete!
      |> Ecto.Changeset.cast(%{y: "updated"}, [:y], [])

    assert_raise ArgumentError, ~r/the changeset has an invalid state/, fn ->
      TestRepo.insert_or_update deleted
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

  test "adds embeds to changeset as empty on insert" do
    TestRepo.insert!(%MyModel{})
    assert Agent.get(CallbackAgent, &get_before_changes/1) ==
      %{id: nil, embed: nil, embeds: [], x: nil, y: nil}
    assert Agent.get(CallbackAgent, &get_after_changes/1) ==
      %{id: nil, x: nil, y: nil}
  end

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

  test "handles embeds on insert" do
    embed = %MyEmbed{x: "xyz"}

    changeset = Ecto.Changeset.change(%MyModel{}, embed: embed)
    model = TestRepo.insert!(changeset)
    assert [{:after_insert, MyModel}, {:after_insert, MyEmbed},
            {:before_insert, MyEmbed}, {:before_insert, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    id = model.embed.id
    assert id
    assert model.embed == %{embed | id: id}

    changeset = Ecto.Changeset.change(%MyModel{}, embeds: [embed])
    model = TestRepo.insert!(changeset)
    assert [{:after_insert, MyModel}, {:after_insert, MyEmbed},
            {:before_insert, MyEmbed}, {:before_insert, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    [%{id: id}] = model.embeds
    assert id
    assert model.embeds == [%{embed | id: id}]
  end

  test "handles embeds on insert when error" do
    embed = %MyEmbed{x: "xyz"}
    embed_changeset = Ecto.Changeset.change(embed)

    # Raises with embeds when inserting model
    assert_raise ArgumentError, ~r"set for embed named `embed`", fn ->
      TestRepo.insert!(%MyModel{embed: embed})
    end

    assert_raise ArgumentError, ~r"set for embed named `embeds`", fn ->
      TestRepo.insert!(%MyModel{embeds: [embed]})
    end

    # Raises if action is update
    changeset = Ecto.Changeset.change(%MyModel{}, embed: embed_changeset)
    changeset = put_in(changeset.changes.embed.action, :update)
    assert_raise ArgumentError, ~r"got action :update in changeset for embedded .* while inserting", fn ->
      TestRepo.insert!(changeset)
    end

    # Raises if action is delete
    changeset = Ecto.Changeset.change(%MyModel{}, embed: embed_changeset)
    changeset = put_in(changeset.changes.embed.action, :delete)
    assert_raise ArgumentError, ~r"got action :delete in changeset for embedded .* while inserting", fn ->
      TestRepo.insert!(changeset)
    end

    # Returns error and rollbacks on invalid constraint
    changeset =
      put_in(%MyModel{}.__meta__.context, {:invalid, [unique: "my_model_foo_index"]})
      |> Ecto.Changeset.change(embed: embed_changeset)
      |> Ecto.Changeset.unique_constraint(:foo)
    assert {:error, changeset} = TestRepo.insert(changeset)
    assert_received {:rollback, ^changeset}
    assert changeset.model.__meta__.state == :built
    assert changeset.changes.embed
    refute changeset.valid?
  end

  test "handles assocs on insert when ok" do
    assoc = %MyAssoc{x: "xyz"}
    inserted_assoc = put_in assoc.__meta__.state, :loaded

    changeset = Ecto.Changeset.change(%MyModel{}, assoc: assoc)
    model = TestRepo.insert!(changeset)
    assert [{:after_insert, MyModel}, {:after_insert, MyAssoc},
            {:before_insert, MyAssoc}, {:before_insert, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    id = model.assoc.id
    assert id
    assert model.assoc == %{inserted_assoc | id: id, my_model_id: model.id}

    changeset = Ecto.Changeset.change(%MyModel{}, assocs: [assoc])
    model = TestRepo.insert!(changeset)
    assert [{:after_insert, MyModel}, {:after_insert, MyAssoc},
            {:before_insert, MyAssoc}, {:before_insert, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    [%{id: id, my_model_id: model_id}] = model.assocs
    assert id
    assert model.id == model_id
    assert model.assocs == [%{inserted_assoc | id: id, my_model_id: model_id}]
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
    assert changeset.changes.assoc
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

  test "handles nested embeds on insert" do
    sub_embed = %SubEmbed{y: "xyz"}
    embed = Ecto.Changeset.change(%MyEmbed{x: "xyz"}, sub_embed: sub_embed)
    changeset = Ecto.Changeset.change(%MyModel{}, embed: embed)
    model = TestRepo.insert!(changeset)
    id = model.embed.sub_embed.id
    assert id
    assert model.embed.sub_embed == %{sub_embed | id: id}
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

  test "skips embeds on update when not changing" do
    embed = %MyEmbed{x: "xyz"}

    # If embed is not in changeset, embeds are left out
    changeset = Ecto.Changeset.change(%MyModel{id: 1, embed: embed}, x: "abc")
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embed == embed

    changeset = Ecto.Changeset.change(%MyModel{id: 1, embeds: [embed]}, x: "abc")
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embeds == [embed]
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

  test "inserting embeds on update" do
    embed = %MyEmbed{x: "xyz"}

    # Inserting the embed
    changeset = Ecto.Changeset.change(%MyModel{id: 1}, embed: embed)
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_insert, MyEmbed},
            {:before_insert, MyEmbed}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    id = model.embed.id
    assert id
    assert model.embed == %{embed | id: id}

    changeset = Ecto.Changeset.change(%MyModel{id: 1}, embeds: [embed])
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_insert, MyEmbed},
            {:before_insert, MyEmbed}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    [%{id: id}] = model.embeds
    assert id
    assert model.embeds == [%{embed | id: id}]

    embed = %{embed | id: @uuid}

    # Replacing embed with a new one
    new_embed = %MyEmbed{x: "abc"}
    changeset = Ecto.Changeset.change(%MyModel{id: 1, embed: embed}, embed: new_embed)
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_delete, MyEmbed},
            {:before_delete, MyEmbed}, {:after_insert, MyEmbed},
            {:before_insert, MyEmbed}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    id = model.embed.id
    assert id
    assert model.embed == %{new_embed | id: id}

    # Replacing embed with nil
    changeset = Ecto.Changeset.change(%MyModel{id: 1, embed: embed}, embed: nil)
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_delete, MyEmbed},
            {:before_delete, MyEmbed}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    refute model.embed
  end

  test "inserting assocs on update" do
    assoc = %MyAssoc{x: "xyz"}
    inserted_assoc = put_in assoc.__meta__.state, :loaded

    # Inserting the assoc
    changeset = Ecto.Changeset.change(%MyModel{id: 1}, assoc: assoc)
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_insert, MyAssoc},
            {:before_insert, MyAssoc}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    id = model.assoc.id
    assert id
    assert model.assoc == %{inserted_assoc | id: id, my_model_id: model.id}

    changeset = Ecto.Changeset.change(%MyModel{id: 1}, assocs: [assoc])
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_insert, MyAssoc},
            {:before_insert, MyAssoc}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    [%{id: id}] = model.assocs
    assert id
    assert model.assocs == [%{inserted_assoc | id: id, my_model_id: model.id}]

    assoc = %{assoc | id: 1}

    # Replacing assoc with a new one
    new_assoc = %MyAssoc{x: "abc"}
    inserted_assoc = put_in new_assoc.__meta__.state, :loaded
    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: assoc}, assoc: new_assoc)
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_delete, MyAssoc},
            {:before_delete, MyAssoc}, {:after_insert, MyAssoc},
            {:before_insert, MyAssoc}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    %{id: id, my_model_id: model_id} = model.assoc
    assert model_id == model.id
    assert model.assoc == %{inserted_assoc | my_model_id: model_id, id: id}

    # Replacing assoc with nil
    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: assoc}, assoc: nil)
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_delete, MyAssoc},
            {:before_delete, MyAssoc}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    refute model.assoc
  end

  test "changing embeds on update" do
    embed = %MyEmbed{x: "xyz"}

    # Raises if there's no id
    embed_changeset = Ecto.Changeset.change(embed, x: "abc")
    changeset = Ecto.Changeset.change(%MyModel{id: 1, embed: embed}, embed: embed_changeset)
    assert_raise Ecto.NoPrimaryKeyValueError, fn ->
      TestRepo.update!(changeset)
    end

    embed = %{embed | id: @uuid}

    # Changing the embed
    embed_changeset = Ecto.Changeset.change(embed, x: "abc")
    changeset = Ecto.Changeset.change(%MyModel{id: 1, embed: embed},
                                      embed: embed_changeset)
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_update, MyEmbed},
            {:before_update, MyEmbed}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embed == %{embed | x: "abc"}

    changeset = Ecto.Changeset.change(%MyModel{id: 1, embeds: [embed]},
                                      embeds: [embed_changeset])
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_update, MyEmbed},
            {:before_update, MyEmbed}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embeds == [%{embed | x: "abc"}]

    # With no changes
    no_changes = Ecto.Changeset.change(embed)
    changeset = Ecto.Changeset.change(%MyModel{id: 1, embed: embed},
                                      embed: no_changes, x: "abc")
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embed == embed

    changes = Ecto.Changeset.change(embed, x: "abc")
    changeset = Ecto.Changeset.change(%MyModel{id: 1, embeds: [embed]},
                                      embeds: [no_changes, changes])
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_insert, MyEmbed},
            {:before_insert, MyEmbed}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embeds == [embed, %{embed | x: "abc"}]
  end

  test "changing assocs on update" do
    assoc = %MyAssoc{x: "xyz"}

    # Raises if there's no id
    assoc_changeset = Ecto.Changeset.change(assoc, x: "abc")
    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: assoc}, assoc: assoc_changeset)
    assert_raise Ecto.NoPrimaryKeyValueError, fn ->
      TestRepo.update!(changeset)
    end

    assoc = %{assoc | id: 1}
    inserted_assoc = %{assoc | my_model_id: 1}
    inserted_assoc = put_in inserted_assoc.__meta__.state, :loaded

    # Changing the assoc
    assoc_changeset = Ecto.Changeset.change(inserted_assoc, x: "abc")
    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: inserted_assoc},
                                      assoc: assoc_changeset)
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_update, MyAssoc},
            {:before_update, MyAssoc}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.assoc == %{inserted_assoc | x: "abc"}

    changeset = Ecto.Changeset.change(%MyModel{id: 1, assocs: [inserted_assoc]},
                                      assocs: [assoc_changeset])
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_update, MyAssoc},
            {:before_update, MyAssoc}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.assocs == [%{inserted_assoc | x: "abc"}]

    # With no changes
    no_changes = Ecto.Changeset.change(inserted_assoc)
    changeset = Ecto.Changeset.change(%MyModel{id: 1, assoc: inserted_assoc},
                                      assoc: no_changes, x: "abc")
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.assoc == inserted_assoc

    new_changeset = Ecto.Changeset.change(assoc, x: "abc")
    changeset = Ecto.Changeset.change(%MyModel{id: 1, assocs: [inserted_assoc]},
                                      assocs: [no_changes, new_changeset])
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_insert, MyAssoc},
            {:before_insert, MyAssoc}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.assocs == [inserted_assoc, %{inserted_assoc | x: "abc"}]
  end

  test "removing embeds on update" do
    embed = %MyEmbed{x: "xyz"}

    # Raises if there's no id
    changeset = Ecto.Changeset.change(%MyModel{id: 1, embed: embed}, embed: nil)
    assert_raise Ecto.NoPrimaryKeyValueError, fn ->
      TestRepo.update!(changeset)
    end

    embed = %{embed | id: @uuid}

    # Deleting the embed
    changeset = Ecto.Changeset.change(%MyModel{id: 1, embed: embed}, embed: nil)
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_delete, MyEmbed},
            {:before_delete, MyEmbed}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embed == nil

    changeset = Ecto.Changeset.change(%MyModel{id: 1, embeds: [embed]}, embeds: [])
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_delete, MyEmbed},
            {:before_delete, MyEmbed}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embeds == []
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
    assert [{:after_update, MyModel}, {:after_delete, MyAssoc},
            {:before_delete, MyAssoc}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.assoc == nil

    changeset = Ecto.Changeset.change(%MyModel{id: 1, assocs: [assoc]}, assocs: [])
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_delete, MyAssoc},
            {:before_delete, MyAssoc}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.assocs == []
  end

  test "handles embeds on update when error" do
    embed = %MyEmbed{x: "xyz"}

    # Returns error and rollbacks on invalid constraint
    embed_changeset = Ecto.Changeset.change(embed)
    my_model = %MyModel{id: 1, embed: nil}
    changeset =
      put_in(my_model.__meta__.context, {:invalid, [unique: "my_model_foo_index"]})
      |> Ecto.Changeset.change(embed: embed_changeset, x: "foo")
      |> Ecto.Changeset.unique_constraint(:foo)
    assert {:error, changeset} = TestRepo.update(changeset)
    assert_received {:rollback, ^changeset}
    assert changeset.changes.embed
    refute changeset.valid?
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

  test "handles nested embeds on update" do
    sub_embed = %SubEmbed{y: "xyz"}
    embed = %MyEmbed{id: @uuid, x: "xyz"}
    embed_changeset = Ecto.Changeset.change(embed, sub_embed: sub_embed)
    changeset = Ecto.Changeset.change(%MyModel{id: 1, embed: embed}, embed: embed_changeset)
    model = TestRepo.update!(changeset)
    id = model.embed.sub_embed.id
    assert model.embed.sub_embed == %{sub_embed | id: id}
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

  test "handles embeds on delete" do
    embed = %MyEmbed{id: @uuid, x: "xyz"}

    # With model runs all callbacks
    model = TestRepo.delete!(%MyModel{id: 1, embed: embed})
    assert [{:after_delete, MyModel}, {:after_delete, MyEmbed},
            {:before_delete, MyEmbed},{:before_delete, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embed == embed

    model = TestRepo.delete!(%MyModel{id: 1, embeds: [embed]})
    assert [{:after_delete, MyModel}, {:after_delete, MyEmbed},
            {:before_delete, MyEmbed},{:before_delete, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embeds == [embed]

    # With changeset runs all callbacks
    changeset = Ecto.Changeset.change(%MyModel{id: 1, embed: embed})
    model = TestRepo.delete!(changeset)
    assert [{:after_delete, MyModel}, {:after_delete, MyEmbed},
            {:before_delete, MyEmbed},{:before_delete, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embed == embed

    changeset = Ecto.Changeset.change(%MyModel{id: 1, embeds: [embed]})
    model = TestRepo.delete!(changeset)
    assert [{:after_delete, MyModel}, {:after_delete, MyEmbed},
            {:before_delete, MyEmbed},{:before_delete, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embeds == [embed]
  end

  test "handles nested embeds on delete" do
    sub_embed = %SubEmbed{id: @uuid, y: "xyz"}
    embed = %MyEmbed{id: @uuid, x: "xyz", sub_embed: sub_embed}
    TestRepo.delete!(%MyModel{id: 1, embed: embed})
    assert [{:after_delete, MyModel}, {:after_delete, MyEmbed},
            {:after_delete, SubEmbed}, {:before_delete, SubEmbed},
            {:before_delete, MyEmbed}, {:before_delete, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
  end
end
