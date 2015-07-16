Code.require_file "../support/test_repo.exs", __DIR__

defmodule Ecto.RepoTest.MyModel do
  use Ecto.Model

  schema "my_model" do
    field :x, :string
    field :y, :binary
    field :z, Ecto.UUID, autogenerate: true
  end

  before_insert :store_autogenerate

  before_insert :store_action
  before_update :store_action
  before_delete :store_action

  def store_autogenerate(changeset) do
    Process.put(:autogenerate_z, changeset.changes.z)
    changeset
  end

  def store_action(changeset) do
    Process.put(:changeset_action, changeset.action)
    changeset
  end
end

defmodule Ecto.RepoTest.MyModelNoPK do
  use Ecto.Model

  @primary_key false
  schema "my_model" do
    field :x, :string
  end
end

defmodule Ecto.RepoTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  require Ecto.TestRepo, as: TestRepo

  alias Ecto.RepoTest.MyModel
  alias Ecto.RepoTest.MyModelNoPK

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
    TestRepo.update!(model)
    TestRepo.delete!(model)
    TestRepo.get(MyModel, 123)
    TestRepo.get_by(MyModel, x: "abc")
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

  test "validate model types" do
    model = %MyModel{x: 123}

    assert_raise Ecto.ChangeError, fn ->
      TestRepo.insert!(model)
    end

    model = %MyModel{id: 1, x: 123}

    assert_raise Ecto.ChangeError, fn ->
      TestRepo.update!(model)
    end
  end

  test "repo validates get" do
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

  test "repo validates update_all" do
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

  test "repo validates delete_all" do
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

  test "create and update accepts changesets" do
    valid = Ecto.Changeset.cast(%MyModel{id: 1}, %{}, [], [])
    TestRepo.insert!(valid)
    TestRepo.update!(valid)
  end

  test "create and update fail on invalid changeset" do
    invalid = %Ecto.Changeset{valid?: false, model: %MyModel{}}

    assert_raise ArgumentError, "cannot insert/update an invalid changeset", fn ->
      TestRepo.insert!(invalid)
    end

    assert_raise ArgumentError, "cannot insert/update an invalid changeset", fn ->
      TestRepo.update!(invalid)
    end
  end

  test "create and update fail on changeset without model" do
    invalid = %Ecto.Changeset{valid?: true, model: nil}

    assert_raise ArgumentError, "cannot insert/update a changeset without a model", fn ->
      TestRepo.insert!(invalid)
    end

    assert_raise ArgumentError, "cannot insert/update a changeset without a model", fn ->
      TestRepo.update!(invalid)
    end
  end

  ## Autogenerate

  test "autogenerates values" do
    model = TestRepo.insert!(%MyModel{})
    assert Process.get(:autogenerate_z)
    assert byte_size(model.z) == 36

    changeset = Ecto.Changeset.cast(%MyModel{}, %{}, [], [])
    model = TestRepo.insert!(changeset)
    assert Process.get(:autogenerate_z)
    assert byte_size(model.z) == 36

    changeset = Ecto.Changeset.cast(%MyModel{}, %{z: nil}, [], [])
    model = TestRepo.insert!(changeset)
    assert Process.get(:autogenerate_z)
    assert byte_size(model.z) == 36

    changeset = Ecto.Changeset.cast(%MyModel{}, %{z: "30313233-3435-3637-3839-616263646566"}, [:z], [])
    model = TestRepo.insert!(changeset)
    assert model.z == "30313233-3435-3637-3839-616263646566"
  end

  ## Status

  test "uses correct action" do
    TestRepo.insert!(%MyModel{})
    assert Process.get(:changeset_action) == :insert

    changeset = Ecto.Changeset.cast(%MyModel{}, %{}, [], [])
    TestRepo.insert!(changeset)
    assert Process.get(:changeset_action) == :insert

    TestRepo.update!(%MyModel{id: 1})
    assert Process.get(:changeset_action) == :update

    changeset = Ecto.Changeset.cast(%MyModel{id: 1}, %{}, [], [])
    TestRepo.update!(changeset)
    assert Process.get(:changeset_action) == :update

    TestRepo.delete!(%MyModel{id: 1})
    assert Process.get(:changeset_action) == :delete

    changeset = Ecto.Changeset.cast(%MyModel{id: 1}, %{}, [], [])
    TestRepo.delete!(changeset)
    assert Process.get(:changeset_action) == :delete
  end
end
