Code.require_file "../support/mock_repo.exs", __DIR__

defmodule Ecto.RepoTest.MyModel do
  use Ecto.Model

  schema "my_model" do
    field :x, :string
    field :y, :binary
    field :z, Ecto.UUID, autogenerate: true
  end

  before_insert :store_autogenerate

  def store_autogenerate(changeset) do
    Process.put(:autogenerate_z, changeset.changes.z)
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
  require Ecto.MockRepo, as: MockRepo

  alias Ecto.RepoTest.MyModel
  alias Ecto.RepoTest.MyModelNoPK

  test "needs model with primary key field" do
    model = %MyModelNoPK{x: "abc"}

    assert_raise Ecto.NoPrimaryKeyError, fn ->
      MockRepo.update!(model)
    end

    assert_raise Ecto.NoPrimaryKeyError, fn ->
      MockRepo.delete!(model)
    end

    assert_raise Ecto.NoPrimaryKeyError, fn ->
      MockRepo.get(MyModelNoPK, 123)
    end
  end

  test "works with primary key value" do
    model = %MyModel{id: 1, x: "abc"}
    MockRepo.update!(model)
    MockRepo.delete!(model)
    MockRepo.get(MyModel, 123)
    MockRepo.get_by(MyModel, x: "abc")
  end

  test "works with custom source model" do
    model = %MyModel{id: 1, x: "abc", __meta__: %Ecto.Schema.Metadata{source: "custom_model"}}
    MockRepo.update!(model)
    MockRepo.delete!(model)

    to_insert = %MyModel{x: "abc", __meta__: %Ecto.Schema.Metadata{source: "custom_model"}}
    MockRepo.insert!(to_insert)
  end

  test "fails without primary key value" do
    model = %MyModel{x: "abc"}

    assert_raise Ecto.MissingPrimaryKeyError, fn ->
      MockRepo.update!(model)
    end

    assert_raise Ecto.MissingPrimaryKeyError, fn ->
      MockRepo.delete!(model)
    end
  end

  test "validate model types" do
    model = %MyModel{x: 123}

    assert_raise Ecto.ChangeError, fn ->
      MockRepo.insert!(model)
    end

    model = %MyModel{id: 1, x: 123}

    assert_raise Ecto.ChangeError, fn ->
      MockRepo.update!(model)
    end
  end

  test "repo validates get" do
    MockRepo.get(MyModel, 123)

    message = ~r"value `:atom` in `where` cannot be cast to type :id in query"
    assert_raise Ecto.CastError, message, fn ->
      MockRepo.get(MyModel, :atom)
    end

    message = ~r"expected a from expression with a model in query"
    assert_raise Ecto.QueryError, message, fn ->
      MockRepo.get(%Ecto.Query{}, :atom)
    end
  end

  test "repo validates update_all" do
    # Success
    MockRepo.update_all(e in MyModel, x: nil)
    MockRepo.update_all(e in MyModel, x: e.x)
    MockRepo.update_all(e in MyModel, x: "123")
    MockRepo.update_all(MyModel, x: "123")
    MockRepo.update_all("my_model", x: "123")

    query = from(e in MyModel, where: e.x == "123")
    MockRepo.update_all(query, x: "")

    # Failures
    message = "no fields given to `update_all`"
    assert_raise ArgumentError, message, fn ->
      MockRepo.update_all(from(e in MyModel, select: e), [])
    end

    assert_raise ArgumentError, "value `123` in `update_all` cannot be cast to type :string", fn ->
      MockRepo.update_all(p in MyModel, x: ^123)
    end

    message = ~r"`update_all` allows only `where` and `join` expressions in query"
    assert_raise Ecto.QueryError, message, fn ->
      MockRepo.update_all(from(e in MyModel, order_by: e.x), x: "123")
    end

    message = "field `Ecto.RepoTest.MyModel.w` in `update_all` does not exist in the model source"
    assert_raise Ecto.ChangeError, message, fn ->
      MockRepo.update_all(MyModel, w: "123")
    end

    message = "field `Ecto.RepoTest.MyModel.y` in `update_all` does not type check. " <>
              "It has type :binary but a type :string was given"
    assert_raise Ecto.ChangeError, message, fn ->
      MockRepo.update_all(MyModel, y: "123")
    end
  end

  test "repo validates delete_all" do
    # Success
    MockRepo.delete_all(MyModel)

    query = from(e in MyModel, where: e.x == "123")
    MockRepo.delete_all(query)

    # Failures
    assert_raise Ecto.QueryError, fn ->
      MockRepo.delete_all from(e in MyModel, select: e)
    end

    assert_raise Ecto.QueryError, fn ->
      MockRepo.delete_all from(e in MyModel, order_by: e.x)
    end
  end

  ## Changesets

  test "create and update accepts changesets" do
    valid = Ecto.Changeset.cast(%MyModel{id: 1}, %{}, [], [])
    MockRepo.insert!(valid)
    MockRepo.update!(valid)
  end

  test "create and update fail on invalid changeset" do
    invalid = %Ecto.Changeset{valid?: false, model: %MyModel{}}

    assert_raise ArgumentError, "cannot insert/update an invalid changeset", fn ->
      MockRepo.insert!(invalid)
    end

    assert_raise ArgumentError, "cannot insert/update an invalid changeset", fn ->
      MockRepo.update!(invalid)
    end
  end

  test "create and update fail on changeset without model" do
    invalid = %Ecto.Changeset{valid?: true, model: nil}

    assert_raise ArgumentError, "cannot insert/update a changeset without a model", fn ->
      MockRepo.insert!(invalid)
    end

    assert_raise ArgumentError, "cannot insert/update a changeset without a model", fn ->
      MockRepo.update!(invalid)
    end
  end

  ## Autogenerate

  test "autogenerates values" do
    model = MockRepo.insert!(%MyModel{})
    assert Process.get(:autogenerate_z)
    assert byte_size(model.z) == 36

    changeset = Ecto.Changeset.cast(%MyModel{}, %{}, [], [])
    model = MockRepo.insert!(changeset)
    assert Process.get(:autogenerate_z)
    assert byte_size(model.z) == 36

    changeset = Ecto.Changeset.cast(%MyModel{}, %{z: nil}, [], [])
    model = MockRepo.insert!(changeset)
    assert Process.get(:autogenerate_z)
    assert byte_size(model.z) == 36

    changeset = Ecto.Changeset.cast(%MyModel{}, %{z: "30313233-3435-3637-3839-616263646566"}, [:z], [])
    model = MockRepo.insert!(changeset)
    assert model.z == "30313233-3435-3637-3839-616263646566"
  end
end
