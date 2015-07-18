defmodule Ecto.RepoTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  require Ecto.TestRepo, as: TestRepo

  defmodule MyEmbed do
    use Ecto.Model

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "" do
      field :x, :string
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
      embeds_one :embed, MyEmbed
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
    Agent.start(fn -> [] end, name: CallbackAgent)
    :ok
  end

  test "needs model with primary key field" do
    model = %MyModelNoPK{x: "abc"}

    assert_raise Ecto.NoPrimaryKeyError, fn ->
      TestRepo.update!(model)
    end

    assert_raise Ecto.NoPrimaryKeyError, fn ->
      TestRepo.delete!(model)
    end

    assert_raise Ecto.NoPrimaryKeyError, fn ->
      TestRepo.get(MyModelNoPK, 123)
    end
  end

  test "works with primary key value" do
    model = %MyModel{id: 1, x: "abc"}
    TestRepo.get(MyModel, 123)
    TestRepo.get_by(MyModel, x: "abc")
    TestRepo.update!(model)
    TestRepo.delete!(model)
  end

  test "works with custom source model" do
    model = %MyModel{id: 1, x: "abc"} |> Ecto.Model.put_source("custom_model")
    TestRepo.update!(model)
    TestRepo.delete!(model)

    to_insert = %MyModel{x: "abc"} |> Ecto.Model.put_source("custom_model")
    TestRepo.insert!(to_insert)
  end

  test "fails without primary key value" do
    model = %MyModel{x: "abc"}

    assert_raise Ecto.MissingPrimaryKeyError, fn ->
      TestRepo.update!(model)
    end

    assert_raise Ecto.MissingPrimaryKeyError, fn ->
      TestRepo.delete!(model)
    end
  end

  test "validates model types" do
    model = %MyModel{x: 123}

    assert_raise Ecto.ChangeError, fn ->
      TestRepo.insert!(model)
    end

    model = %MyModel{id: 1, x: 123}

    assert_raise Ecto.ChangeError, fn ->
      TestRepo.update!(model)
    end
  end

  test "validates get" do
    TestRepo.get(MyModel, 123)

    message = ~r"value `:atom` in `where` cannot be cast to type :id in query"
    assert_raise Ecto.CastError, message, fn ->
      TestRepo.get(MyModel, :atom)
    end

    message = ~r"expected a from expression with a model in query"
    assert_raise Ecto.QueryError, message, fn ->
      TestRepo.get(%Ecto.Query{}, :atom)
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

  test "insert and update accepts changesets" do
    valid = Ecto.Changeset.cast(%MyModel{id: 1}, %{}, [], [])
    assert {:ok, %MyModel{}} = TestRepo.insert(valid)
    assert {:ok, %MyModel{}} = TestRepo.update(valid)
  end

  test "insert and update error on invalid changeset" do
    invalid = %Ecto.Changeset{valid?: false, model: %MyModel{}}
    assert {:error, ^invalid} = TestRepo.insert(invalid)
    assert {:error, ^invalid} = TestRepo.update(invalid)
  end

  test "insert! and update! accepts changesets" do
    valid = Ecto.Changeset.cast(%MyModel{id: 1}, %{}, [], [])
    assert %MyModel{} = TestRepo.insert!(valid)
    assert %MyModel{} = TestRepo.update!(valid)
  end

  test "insert! and update! fail on invalid changeset" do
    invalid = %Ecto.Changeset{valid?: false, model: %MyModel{}}

    assert_raise Ecto.InvalidChangesetError,
                 ~r"could not perform insert because changeset is invalid", fn ->
      TestRepo.insert!(invalid)
    end

    assert_raise Ecto.InvalidChangesetError,
                 ~r"could not perform update because changeset is invalid", fn ->
      TestRepo.update!(invalid)
    end
  end

  test "insert and update fail on changeset without model" do
    invalid = %Ecto.Changeset{valid?: true, model: nil}

    assert_raise ArgumentError, "cannot insert/update a changeset without a model", fn ->
      TestRepo.insert!(invalid)
    end

    assert_raise ArgumentError, "cannot insert/update a changeset without a model", fn ->
      TestRepo.update!(invalid)
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

    TestRepo.update!(%MyModel{id: 1})
    assert Agent.get(CallbackAgent, get_action) == {:after_update, :update}

    changeset = Ecto.Changeset.cast(%MyModel{id: 1}, %{}, [], [])
    TestRepo.update!(changeset)
    assert Agent.get(CallbackAgent, get_action) == {:after_update, :update}

    TestRepo.delete!(%MyModel{id: 1})
    assert Agent.get(CallbackAgent, get_action) == {:after_delete, :delete}

    changeset = Ecto.Changeset.cast(%MyModel{id: 1}, %{}, [], [])
    TestRepo.delete!(changeset)
    assert Agent.get(CallbackAgent, get_action) == {:after_delete, :delete}
  end

  defp get_changes([{_, changeset} | _]), do: changeset.changes

  test "adds embeds to changeset as empty on insert" do
    TestRepo.insert!(%MyModel{embed: %MyEmbed{}})
    assert Agent.get(CallbackAgent, &get_changes/1) == %{id: nil, embed: nil, x: nil, y: nil}
  end

  test "skip adding embeds to changeset on update" do
    TestRepo.update!(%MyModel{id: 5, embed: %MyEmbed{}})
    assert Agent.get(CallbackAgent, &get_changes/1) == %{x: nil, y: nil}
  end

  defp get_models(changesets) do
    Enum.map(changesets, fn {stage, changeset} ->
      {stage, changeset.model.__struct__}
    end)
  end

  test "handles embeds on insert" do
    embed = %MyEmbed{x: "xyz"}

    # Rejects embeds when inserting model
    model = TestRepo.insert!(%MyModel{embed: embed})
    assert [{:after_insert, MyModel}, {:before_insert, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embed == nil

    # Only if embed is in changeset
    changeset = Ecto.Changeset.change(%MyModel{embed: embed})
    model = TestRepo.insert!(changeset)
    assert [{:after_insert, MyModel}, {:before_insert, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embed == nil

    changeset = Ecto.Changeset.change(%MyModel{}, embed: embed)
    model = TestRepo.insert!(changeset)
    assert [{:after_insert, MyModel}, {:after_insert, MyEmbed},
            {:before_insert, MyEmbed}, {:before_insert, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embed == embed
  end

  test "handles embeds on update" do
    embed = %MyEmbed{id: @uuid, x: "xyz"}

    # Leaves embeds untouched when updatting model
    model = TestRepo.update!(%MyModel{id: 1, embed: embed})
    assert [{:after_update, MyModel}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embed == embed

    # If embed is not in changeset, embeds are left out
    changeset = Ecto.Changeset.change(%MyModel{id: 1, embed: embed}, x: "abc")
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embed == embed

    # Inserting the embed
    changeset = Ecto.Changeset.change(%MyModel{id: 1}, embed: embed)
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_insert, MyEmbed},
            {:before_insert, MyEmbed}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embed == embed

    # Changeing the embed
    embed_changeset = Ecto.Changeset.change(embed, x: "abc")
    changeset = Ecto.Changeset.change(%MyModel{id: 1, embed: embed}, embed: embed_changeset)
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_update, MyEmbed},
            {:before_update, MyEmbed}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embed == %MyEmbed{x: "abc", id: @uuid}

    # Deleting the embed
    changeset = Ecto.Changeset.change(%MyModel{id: 1, embed: embed}, embed: nil)
    model = TestRepo.update!(changeset)
    assert [{:after_update, MyModel}, {:after_delete, MyEmbed},
            {:before_delete, MyEmbed}, {:before_update, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embed == nil
  end

  test "handles embeds on delete" do
    embed = %MyEmbed{id: @uuid, x: "xyz"}

    # With model runs all callbacks
    model = TestRepo.delete!(%MyModel{id: 1, embed: embed})
    assert [{:after_delete, MyModel}, {:after_delete, MyEmbed},
            {:before_delete, MyEmbed}, {:before_delete, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embed == nil

    # With changeset runs all callbacks
    changeset = Ecto.Changeset.change(%MyModel{id: 1, embed: embed})
    model = TestRepo.delete!(changeset)
    assert [{:after_delete, MyModel}, {:after_delete, MyEmbed},
            {:before_delete, MyEmbed}, {:before_delete, MyModel} | _] =
      Agent.get(CallbackAgent, &get_models/1)
    assert model.embed == nil
  end
end
