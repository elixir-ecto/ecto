defmodule Ecto.RepoTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto, only: [put_meta: 2]
  require Ecto.TestRepo, as: TestRepo

  defmodule MyModel do
    use Ecto.Schema

    schema "my_model" do
      field :x, :string
      field :y, :binary
    end
  end

  defmodule MyModelNoPK do
    use Ecto.Schema

    @primary_key false
    schema "my_model" do
      field :x, :string
    end
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
    TestRepo.get_by(MyModel, %{id: 123})

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

  test "insert_or_update uses the correct action" do
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

  defp prepare_changeset() do
    %MyModel{id: 1}
    |> Ecto.Changeset.cast(%{x: "one"}, [:x], [])
    |> Ecto.Changeset.prepare_changes(fn %{repo: repo} = changeset ->
          Process.put(:ecto_repo, repo)
          Process.put(:ecto_counter, 1)
          changeset
        end)
    |> Ecto.Changeset.prepare_changes(fn changeset ->
          Process.put(:ecto_counter, 2)
          changeset
        end)
  end

  test "insert runs prepare callbacks in transaction" do
    changeset = prepare_changeset()
    TestRepo.insert!(changeset)
    assert_received {:transaction, _}
    assert Process.get(:ecto_repo) == TestRepo
    assert Process.get(:ecto_counter) == 2
  end

  test "update runs prepare callbacks in transaction" do
    changeset = prepare_changeset()
    TestRepo.update!(changeset)
    assert_received {:transaction, _}
    assert Process.get(:ecto_repo) == TestRepo
    assert Process.get(:ecto_counter) == 2
  end

  test "delete runs prepare callbacks in transaction" do
    changeset = prepare_changeset()
    TestRepo.delete!(changeset)
    assert_received {:transaction, _}
    assert Process.get(:ecto_repo) == TestRepo
    assert Process.get(:ecto_counter) == 2
  end
end
