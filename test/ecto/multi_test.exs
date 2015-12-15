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

  test "Repo.transaction" do
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

  #TODO failing cases
end
