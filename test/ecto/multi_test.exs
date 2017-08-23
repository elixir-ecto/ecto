defmodule Ecto.MultiTest do
  use ExUnit.Case, async: true
  doctest Ecto.Multi

  alias Ecto.Multi
  alias Ecto.Changeset
  alias Ecto.TestRepo

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field :x, :integer
      field :parent_x, :integer
    end
  end

  def ok(x), do: {:ok, x}
  def multi(x), do: Multi.new |> Multi.update(:update, Changeset.change(x.insert))

  test "new" do
    assert Multi.new == %Multi{}
  end

  test "insert changeset" do
    changeset = Changeset.change(%Comment{})
    multi     =
      Multi.new
      |> Multi.insert(:comment, changeset)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, {:changeset, %{changeset | action: :insert}, []}}]
  end

  test "insert struct" do
    struct    = %Comment{}
    changeset = Changeset.change(struct)
    multi     =
      Multi.new
      |> Multi.insert(:comment, struct)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, {:changeset, %{changeset | action: :insert}, []}}]
  end

  test "update changeset" do
    changeset = Changeset.change(%Comment{})
    multi     =
      Multi.new
      |> Multi.update(:comment, changeset)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, {:changeset, %{changeset | action: :update}, []}}]
  end

  test "insert_or_update changeset will insert the changeset if not loaded" do
    changeset = Changeset.change(%Comment{})
    multi     =
      Multi.new
      |> Multi.insert_or_update(:comment, changeset)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, {:changeset, %{changeset | action: :insert}, []}}]
  end

  test "insert_or_update changeset will update the changeset if it was loaded" do
    changeset = Changeset.change(%Comment{id: 1}, x: 2)
    changeset = put_in(changeset.data.__meta__.state, :loaded)
    multi     =
      Multi.new
      |> Multi.insert_or_update(:comment, changeset)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, {:changeset, %{changeset | action: :update}, []}}]
  end

  test "delete changeset" do
    changeset = Changeset.change(%Comment{})
    multi     =
      Multi.new
      |> Multi.delete(:comment, changeset)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, {:changeset, %{changeset | action: :delete}, []}}]
  end

  test "delete struct" do
    struct    = %Comment{}
    changeset = Changeset.change(struct)
    multi     =
      Multi.new
      |> Multi.delete(:comment, struct)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, {:changeset, %{changeset | action: :delete}, []}}]
  end

  test "error" do
    multi =
      Multi.new
      |> Multi.error(:oops, :value)

    assert multi.names      == MapSet.new([:oops])
    assert multi.operations == [{:oops, {:error, :value}}]
  end

  test "run with fun" do
    fun = fn changes -> {:ok, changes} end
    multi =
      Multi.new
      |> Multi.run(:fun, fun)

    assert multi.names      == MapSet.new([:fun])
    assert multi.operations == [{:fun, {:run, fun}}]
  end

  test "run named with tuple" do
    fun = fn changes -> {:ok, changes} end
    multi =
      Multi.new
      |> Multi.run({:fun, 3}, fun)

    assert multi.names      == MapSet.new([{:fun, 3}])
    assert multi.operations == [{{:fun, 3}, {:run, fun}}]
  end

  test "run named with char_list" do
    fun = fn changes -> {:ok, changes} end
    multi =
      Multi.new
      |> Multi.run('myFunction', fun)

    assert multi.names      == MapSet.new(['myFunction'])
    assert multi.operations == [{'myFunction', {:run, fun}}]
  end

  test "run with mfa" do
    multi =
      Multi.new
      |> Multi.run(:fun, __MODULE__, :ok, [])

    assert multi.names      == MapSet.new([:fun])
    assert multi.operations == [{:fun, {:run, {__MODULE__, :ok, []}}}]
  end

  test "insert_all" do
    multi =
      Multi.new
      |> Multi.insert_all(:comments, Comment, [[x: 2]])

    assert multi.names == MapSet.new([:comments])
    assert [{:comments, {:insert_all, Comment, [[x: 2]], []}}] = multi.operations
  end

  test "update_all" do
    multi =
      Multi.new
      |> Multi.update_all(:comments, Comment, set: [x: 2])

    assert multi.names == MapSet.new([:comments])
    assert [{:comments, {:update_all, query, updates, []}}] = multi.operations
    assert updates == [set: [x: 2]]
    assert query   == Ecto.Queryable.to_query(Comment)
  end

  test "delete_all" do
    multi =
      Multi.new
      |> Multi.delete_all(:comments, Comment)

    assert multi.names == MapSet.new([:comments])
    assert [{:comments, {:delete_all, query, []}}] = multi.operations
    assert query == Ecto.Queryable.to_query(Comment)
  end

  test "append/prepend without repetition" do
    fun = fn _ -> {:ok, :ok} end
    lhs = Multi.new |> Multi.run(:one, fun) |> Multi.run(:two, fun)
    rhs = Multi.new |> Multi.run(:three, fun) |> Multi.run(:four, fun)

    merged     = Multi.append(lhs, rhs)
    operations = Keyword.keys(merged.operations)
    assert merged.names == MapSet.new([:one, :two, :three, :four])
    assert operations   == [:four, :three, :two, :one]

    merged     = Multi.prepend(lhs, rhs)
    operations = Keyword.keys(merged.operations)
    assert merged.names == MapSet.new([:one, :two, :three, :four])
    assert operations   == [:two, :one, :four, :three]
  end

  test "append/prepend with repetition" do
    fun   = fn _ -> {:ok, :ok} end
    multi = Multi.new |> Multi.run(:run, fun)

    assert_raise ArgumentError, ~r"both declared operations: \[:run\]", fn ->
      Multi.append(multi, multi)
    end

    assert_raise ArgumentError, ~r"both declared operations: \[:run\]", fn ->
      Multi.prepend(multi, multi)
    end
  end

  test "to_list" do
    changeset = Changeset.change(%Comment{id: 1}, x: 1)
    multi =
      Multi.new
      |> Multi.insert(:insert, changeset)
      |> Multi.run(:run, fn changes -> {:ok, changes} end)
      |> Multi.update(:update, changeset)
      |> Multi.delete(:delete, changeset)
      |> Multi.insert_all(:insert_all, Comment, [[x: 1]])
      |> Multi.update_all(:update_all, Comment, set: [x: 1])
      |> Multi.delete_all(:delete_all, Comment)

    assert [
      {:insert,     {:insert, _, []}},
      {:run,        {:run, _}},
      {:update,     {:update, _, []}},
      {:delete,     {:delete, _, []}},
      {:insert_all, {:insert_all, _, _, []}},
      {:update_all, {:update_all, _, _, []}},
      {:delete_all, {:delete_all, _, []}},
    ] = Ecto.Multi.to_list(multi)
  end

  test "add changeset with invalid action" do
    changeset = %{Changeset.change(%Comment{}) | action: :invalid}

    assert_raise ArgumentError, ~r"an action already set to :invalid", fn ->
      Multi.new |> Multi.insert(:changeset, changeset)
    end
  end

  test "add run with invalid arity" do
    assert_raise FunctionClauseError, fn ->
      Multi.new |> Multi.run(:run, fn -> nil end)
    end
  end

  test "repeating an operation" do
    fun = fn _ -> {:ok, :ok} end
    assert_raise RuntimeError, ~r":run is already a member", fn ->
      Multi.new |> Multi.run(:run, fun) |> Multi.run(:run, fun)
    end
  end

  describe "merge/2" do
    test "with fun" do
      changeset = Changeset.change(%Comment{})
      multi =
        Multi.new
        |> Multi.insert(:insert, changeset)
        |> Multi.merge(fn data ->
          Multi.new |> Multi.update(:update, Changeset.change(data.insert))
        end)

      assert {:ok, data} = TestRepo.transaction(multi)
      assert %Comment{} = data.insert
      assert %Comment{} = data.update
    end

    test "with mfa" do
      changeset = Changeset.change(%Comment{})
      multi =
        Multi.new
        |> Multi.insert(:insert, changeset)
        |> Multi.merge(__MODULE__, :multi, [])

        assert {:ok, data} = TestRepo.transaction(multi)
        assert %Comment{} = data.insert
        assert %Comment{} = data.update
    end

    test "rollbacks on errors" do
      error = fn _ -> {:error, :error} end
      ok    = fn _ -> {:ok, :ok} end

      multi =
        Multi.new
        |> Multi.run(:outside_ok, ok)
        |> Multi.merge(fn _ ->
          Multi.new
          |> Multi.run(:inside_ok, ok)
          |> Multi.run(:inside_error, error)
        end)
        |> Multi.run(:outside_error, error)

      assert {:error, :inside_error, :error, data} = TestRepo.transaction(multi)
      assert :ok == data.outside_ok
      assert :ok == data.inside_ok
    end

    test "does not allow repeated operations" do
      fun = fn _ -> {:ok, :ok} end

      multi =
        Multi.new
        |> Multi.merge(fn _ ->
          Multi.new |> Multi.run(:run, fun)
        end)
        |> Multi.run(:run, fun)

      assert_raise RuntimeError, ~r"found in both Ecto.Multi: \[:run\]", fn ->
        TestRepo.transaction(multi)
      end

      multi =
        Multi.new
        |> Multi.merge(fn _ -> Multi.new |> Multi.run(:run, fun) end)
        |> Multi.merge(fn _ -> Multi.new |> Multi.run(:run, fun) end)

      assert_raise RuntimeError, ~r"found in both Ecto.Multi: \[:run\]", fn ->
        TestRepo.transaction(multi)
      end
    end
  end

  describe "Repo.transaction" do
    test "on success" do
      changeset = Changeset.change(%Comment{id: 1}, x: 1)
      multi =
        Multi.new
        |> Multi.insert(:insert, changeset)
        |> Multi.run(:run, fn changes -> {:ok, changes} end)
        |> Multi.update(:update, changeset)
        |> Multi.delete(:delete, changeset)
        |> Multi.insert_all(:insert_all, Comment, [[x: 1]])
        |> Multi.update_all(:update_all, Comment, set: [x: 1])
        |> Multi.delete_all(:delete_all, Comment)

      assert {:ok, changes} = TestRepo.transaction(multi)
      assert_received {:transaction, _}
      assert {:messages, actions} = Process.info(self(), :messages)
      assert actions == [{:insert, {nil, "comments"}}, {:update, {nil, "comments"}}, {:delete, {nil, "comments"}}, {:insert_all, {nil, "comments"}, [[x: 1]]},
                         {:update_all, {nil, "comments"}}, {:delete_all, {nil, "comments"}}]
      assert %Comment{} = changes.insert
      assert %Comment{} = changes.update
      assert %Comment{} = changes.delete
      assert {1, nil}   = changes.insert_all
      assert {1, nil}   = changes.update_all
      assert {1, nil}   = changes.delete_all
      assert Map.has_key?(changes.run, :insert)
      refute Map.has_key?(changes.run, :update)
    end

    test "with empty multi" do
      assert {:ok, changes} = TestRepo.transaction(Multi.new)
      refute_received {:transaction, _}
      assert changes == %{}
    end

    test "rolls back from run" do
      changeset = Changeset.change(%Comment{id: 1}, x: 1)
      multi =
        Multi.new
        |> Multi.insert(:insert, changeset)
        |> Multi.run(:run, fn _changes -> {:error, "error from run"} end)
        |> Multi.update(:update, changeset)
        |> Multi.delete(:delete, changeset)

      assert {:error, :run, "error from run", changes} = TestRepo.transaction(multi)
      assert_received {:transaction, _}
      assert_received {:rollback, _}
      assert {:messages, [{:insert, {nil, "comments"}}]} == Process.info(self(), :messages)
      assert %Comment{} = changes.insert
      refute Map.has_key?(changes, :run)
      refute Map.has_key?(changes, :update)
    end

  test "rolls back on error" do
      changeset = Changeset.change(%Comment{id: 1}, x: 1)
      multi =
        Multi.new
        |> Multi.insert(:insert, changeset)
        |> Multi.error(:oops, "explicit error")
        |> Multi.update(:update, changeset)
        |> Multi.delete(:delete, changeset)

      assert {:error, :oops, "explicit error", changes} = TestRepo.transaction(multi)
      assert_received {:transaction, _}
      assert_received {:rollback, _}
      assert {:messages, [{:insert, {nil, "comments"}}]} == Process.info(self(), :messages)
      assert %Comment{} = changes.insert
      refute Map.has_key?(changes, :run)
      refute Map.has_key?(changes, :update)
    end

    test "rolls back from repo" do
      changeset = Changeset.change(%Comment{id: 1}, x: 1)
      invalid   = put_in(changeset.data.__meta__.context, {:invalid, [unique: "comments_x_index"]})
                  |> Changeset.unique_constraint(:x)

      multi =
        Multi.new
        |> Multi.insert(:insert, changeset)
        |> Multi.run(:run, fn _changes -> {:ok, "ok"} end)
        |> Multi.update(:update, invalid)
        |> Multi.delete(:delete, changeset)

      assert {:error, :update, error, changes} = TestRepo.transaction(multi)
      assert_received {:transaction, _}
      assert_received {:rollback, _}
      assert {:messages, [{:insert, {nil, "comments"}}]} == Process.info(self(), :messages)
      assert %Comment{} = changes.insert
      assert "ok" == changes.run
      assert error.errors == [x: {"has already been taken", [constraint: :unique]}]
      refute Map.has_key?(changes, :update)
    end

    test "checks invalid changesets before starting transaction" do
      changeset = %{Changeset.change(%Comment{}) | valid?: false}
      multi = Multi.new |> Multi.insert(:invalid, changeset)

      assert {:error, :invalid, invalid, %{}} = TestRepo.transaction(multi)
      assert invalid.data == changeset.data
      refute_received {:transaction, _}
    end
  end
end
