defmodule Ecto.MultiTest do
  use ExUnit.Case, async: true

  alias Ecto.Multi
  alias Ecto.Changeset
  alias Ecto.TestRepo

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field :x, :integer
    end
  end

  def ok(x), do: {:ok, x}

  test "new" do
    assert Multi.new == %Multi{}
  end

  test "insert changeset" do
    changeset = Changeset.change(%Comment{})
    multi     =
      Multi.new
      |> Multi.insert(:comment, changeset)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, %{changeset | action: :insert}}]
  end

  test "insert struct" do
    struct    = %Comment{}
    changeset = Changeset.change(struct)
    multi     =
      Multi.new
      |> Multi.insert(:comment, struct)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, %{changeset | action: :insert}}]
  end

  test "update changeset" do
    changeset = Changeset.change(%Comment{})
    multi     =
      Multi.new
      |> Multi.update(:comment, changeset)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, %{changeset | action: :update}}]
  end

  test "delete changeset" do
    changeset = Changeset.change(%Comment{})
    multi     =
      Multi.new
      |> Multi.delete(:comment, changeset)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, %{changeset | action: :delete}}]
  end

  test "delete struct" do
    struct    = %Comment{}
    changeset = Changeset.change(struct)
    multi     =
      Multi.new
      |> Multi.delete(:comment, struct)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, %{changeset | action: :delete}}]
  end

  test "run with fun" do
    fun = fn changes, _opts -> {:ok, changes} end
    multi =
      Multi.new
      |> Multi.run(:fun, fun)

    assert multi.names      == MapSet.new([:fun])
    assert multi.operations == [{:fun, fun}]
  end

  test "run with mfa" do
    multi =
      Multi.new
      |> Multi.run(:fun, __MODULE__, :ok, [])

    assert multi.names      == MapSet.new([:fun])
    assert multi.operations == [{:fun, {__MODULE__, :ok, []}}]
  end

  test "Repo.transaction success" do
    changeset = Changeset.change(%Comment{id: 1}, x: 1)
    multi =
      Multi.new
      |> Multi.insert(:insert, changeset)
      |> Multi.run(:run, fn changes, _opts -> {:ok, changes} end)
      |> Multi.update(:update, changeset)
      |> Multi.delete(:delete, changeset)

    assert {:ok, changes} = TestRepo.transaction(multi)
    assert_received {:transaction, _}
    assert {:messages, [:insert, :update, :delete]} == Process.info(self, :messages)
    assert %Comment{} = changes.insert
    assert %Comment{} = changes.update
    assert %Comment{} = changes.delete
    assert Map.has_key?(changes.run, :insert)
    refute Map.has_key?(changes.run, :update)
  end

  test "Repo.transaction rolling back from run" do
    changeset = Changeset.change(%Comment{id: 1}, x: 1)
    multi =
      Multi.new
      |> Multi.insert(:insert, changeset)
      |> Multi.run(:run, fn _changes, _opts -> {:error, "error from run"} end)
      |> Multi.update(:update, changeset)
      |> Multi.delete(:delete, changeset)

    assert {:error, :run, "error from run", changes} = TestRepo.transaction(multi)
    assert_received {:transaction, _}
    assert_received {:rollback, _}
    assert {:messages, [:insert]} == Process.info(self, :messages)
    assert %Comment{} = changes.insert
    refute Map.has_key?(changes, :run)
    refute Map.has_key?(changes, :update)
  end

  test "Repo.transaction rolling back from repo" do
    changeset = Changeset.change(%Comment{id: 1}, x: 1)
    invalid   = put_in(changeset.model.__meta__.context, {:invalid, [unique: "comments_x_index"]})
                |> Changeset.unique_constraint(:x)

    multi =
      Multi.new
      |> Multi.insert(:insert, changeset)
      |> Multi.run(:run, fn _changes, _opts -> {:ok, "ok"} end)
      |> Multi.update(:update, invalid)
      |> Multi.delete(:delete, changeset)

    assert {:error, :update, error, changes} = TestRepo.transaction(multi)
    assert_received {:transaction, _}
    assert_received {:rollback, _}
    assert {:messages, [:insert]} == Process.info(self, :messages)
    assert %Comment{} = changes.insert
    assert "ok" == changes.run
    assert error.errors == [x: "has already been taken"]
    refute Map.has_key?(changes, :update)
  end

  test "checks invalid changesets before starting transaction" do
    changeset = %{Changeset.change(%Comment{}) | valid?: false}
    multi = Multi.new |> Multi.insert(:invalid, changeset)

    assert {:error, :invalid, invalid, %{}} = TestRepo.transaction(multi)
    assert invalid.model == changeset.model
    refute_received {:transaction, _}
  end
end
