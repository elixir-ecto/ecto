defmodule Ecto.MultiTest do
  use ExUnit.Case, async: true
  doctest Ecto.Multi

  alias Ecto.Multi
  alias Ecto.Changeset
  alias Ecto.TestRepo

  require Ecto.Query

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field :x, :integer
      field :parent_x, :integer
    end
  end

  def run_ok(repo, _changes), do: {:ok, repo}
  def multi(changes), do: Multi.new() |> Multi.update(:update, Changeset.change(changes.insert))

  test "new" do
    assert Multi.new() == %Multi{}
  end

  test "insert changeset" do
    changeset = Changeset.change(%Comment{})
    multi     =
      Multi.new()
      |> Multi.insert(:comment, changeset)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, {:changeset, %{changeset | action: :insert}, []}}]
  end

  test "insert struct" do
    struct    = %Comment{}
    changeset = Changeset.change(struct)
    multi     =
      Multi.new()
      |> Multi.insert(:comment, struct)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, {:changeset, %{changeset | action: :insert}, []}}]
  end

  test "insert fun" do
    changeset = Changeset.change(%Comment{})
    fun = fn _changes -> {:ok, changeset} end
    multi =
      Multi.new()
      |> Multi.insert(:fun, fun)

    assert multi.names == MapSet.new([:fun])
    assert [{:fun, {:run, _fun}}] = multi.operations
  end

  test "update changeset" do
    changeset = Changeset.change(%Comment{})
    multi     =
      Multi.new()
      |> Multi.update(:comment, changeset)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, {:changeset, %{changeset | action: :update}, []}}]
  end

  test "update fun" do
    changeset = Changeset.change(%Comment{})
    fun = fn _changes -> {:ok, changeset} end
    multi =
      Multi.new()
      |> Multi.update(:fun, fun)

    assert multi.names == MapSet.new([:fun])
    assert [{:fun, {:run, _fun}}] = multi.operations
  end

  test "insert_or_update changeset will insert the changeset if not loaded" do
    changeset = Changeset.change(%Comment{})
    multi     =
      Multi.new()
      |> Multi.insert_or_update(:comment, changeset)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, {:changeset, %{changeset | action: :insert}, []}}]
  end

  test "inspect prints the multi state and return the base multi" do
    multi =
      Multi.new()
      |> Multi.inspect()

    assert multi.names == MapSet.new([])
    assert multi.operations == [{:inspect, {:inspect, []}}]
  end

  test "insert_or_update changeset will update the changeset if it was loaded" do
    changeset = Changeset.change(%Comment{id: 1}, x: 2)
    changeset = put_in(changeset.data.__meta__.state, :loaded)
    multi     =
      Multi.new()
      |> Multi.insert_or_update(:comment, changeset)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, {:changeset, %{changeset | action: :update}, []}}]
  end

  test "insert_or_update fun" do
    changeset = Changeset.change(%Comment{})
    fun = fn _changes -> {:ok, changeset} end
    multi =
      Multi.new()
      |> Multi.insert_or_update(:fun, fun)

    assert multi.names == MapSet.new([:fun])
    assert [{:fun, {:run, _fun}}] = multi.operations
  end

  test "delete changeset" do
    changeset = Changeset.change(%Comment{})
    multi     =
      Multi.new()
      |> Multi.delete(:comment, changeset)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, {:changeset, %{changeset | action: :delete}, []}}]
  end

  test "delete struct" do
    struct    = %Comment{}
    changeset = Changeset.change(struct)
    multi     =
      Multi.new()
      |> Multi.delete(:comment, struct)

    assert multi.names      == MapSet.new([:comment])
    assert multi.operations == [{:comment, {:changeset, %{changeset | action: :delete}, []}}]
  end

  test "delete fun" do
    changeset = Changeset.change(%Comment{})
    fun = fn _changes -> {:ok, changeset} end
    multi =
      Multi.new()
      |> Multi.delete(:fun, fun)

    assert multi.names == MapSet.new([:fun])
    assert [{:fun, {:run, _fun}}] = multi.operations
  end

  test "one queryable" do
    multi =
      Multi.new()
      |> Multi.one(:comment, Comment)

    assert multi.names == MapSet.new([:comment])
    assert [{:comment, {:run, _fun}}] = multi.operations
  end

  test "one fun" do
    fun = fn _changes -> Comment end

    multi =
      Multi.new()
      |> Multi.one(:comment, fun)

    assert multi.names == MapSet.new([:comment])
    assert [{:comment, {:run, _fun}}] = multi.operations
  end

  test "all queryable" do
    multi =
      Multi.new()
      |> Multi.all(:comments, Comment)

    assert multi.names == MapSet.new([:comments])
    assert [{:comments, {:run, _fun}}] = multi.operations
  end

  test "all fun" do
    fun = fn _changes -> Comment end

    multi =
      Multi.new()
      |> Multi.all(:comments, fun)

    assert multi.names == MapSet.new([:comments])
    assert [{:comments, {:run, _fun}}] = multi.operations
  end

  test "error" do
    multi =
      Multi.new()
      |> Multi.error(:oops, :value)

    assert multi.names      == MapSet.new([:oops])
    assert multi.operations == [{:oops, {:error, :value}}]
  end

  test "run with fun" do
    fun = fn _repo, changes -> {:ok, changes} end
    multi =
      Multi.new()
      |> Multi.run(:fun, fun)

    assert multi.names      == MapSet.new([:fun])
    assert multi.operations == [{:fun, {:run, fun}}]
  end

  test "run named with tuple" do
    fun = fn _repo, changes -> {:ok, changes} end
    multi =
      Multi.new()
      |> Multi.run({:fun, 3}, fun)

    assert multi.names      == MapSet.new([{:fun, 3}])
    assert multi.operations == [{{:fun, 3}, {:run, fun}}]
  end

  test "run named with char_list" do
    fun = fn _repo, changes -> {:ok, changes} end
    multi =
      Multi.new()
      |> Multi.run('myFunction', fun)

    assert multi.names      == MapSet.new(['myFunction'])
    assert multi.operations == [{'myFunction', {:run, fun}}]
  end

  test "run with mfa" do
    multi =
      Multi.new()
      |> Multi.run(:fun, __MODULE__, :run_ok, [])

    assert multi.names      == MapSet.new([:fun])
    assert multi.operations == [{:fun, {:run, {__MODULE__, :run_ok, []}}}]
  end

  test "insert_all" do
    multi =
      Multi.new()
      |> Multi.insert_all(:comments, Comment, [[x: 2]])

    assert multi.names == MapSet.new([:comments])
    assert [{:comments, {:insert_all, Comment, [[x: 2]], []}}] = multi.operations
  end

  test "insert_all fun" do
    fun_entries = fn _changes -> [[x: 2]] end

    multi =
      Multi.new()
      |> Multi.insert_all(:fun, Comment, fun_entries)

    assert multi.names == MapSet.new([:fun])
    assert [{:fun, {:run, _fun}}] = multi.operations

    assert {:ok, changes} = TestRepo.transaction(multi)
    assert_received {:transaction, _}

    assert changes[:fun] == {1, nil}
  end

  test "update_all" do
    multi =
      Multi.new()
      |> Multi.update_all(:comments, Comment, set: [x: 2])

    assert multi.names == MapSet.new([:comments])
    assert [{:comments, {:update_all, query, updates, []}}] = multi.operations
    assert updates == [set: [x: 2]]
    assert query == Ecto.Queryable.to_query(Comment)
  end

  test "update_all fun" do
    fun_queryable = fn _changes -> Ecto.Query.from(c in Comment, update: [set: [x: 2]]) end

    multi =
      Multi.new()
      |> Multi.update_all(:fun, fun_queryable, [])

    assert multi.names == MapSet.new([:fun])
    assert [{:fun, {:run, _fun}}] = multi.operations

    assert {:ok, changes} = TestRepo.transaction(multi)
    assert_received {:transaction, _}

    assert changes[:fun] == {1, nil}
  end

  test "delete_all schema" do
    multi =
      Multi.new()
      |> Multi.delete_all(:comments, Comment)

    assert multi.names == MapSet.new([:comments])
    assert [{:comments, {:delete_all, query, []}}] = multi.operations
    assert query == Ecto.Queryable.to_query(Comment)
  end

  test "delete_all fun" do
    fun = fn _changes -> Comment end

    multi =
      Multi.new()
      |> Multi.delete_all(:fun, fun)

    assert multi.names == MapSet.new([:fun])
    assert [{:fun, {:run, _fun}}] = multi.operations

    assert {:ok, changes} = TestRepo.transaction(multi)
    assert_received {:transaction, _}

    assert changes[:fun] == {1, nil}
  end

  test "append/prepend without repetition" do
    fun = fn _, _ -> {:ok, :ok} end
    lhs = Multi.new() |> Multi.run(:one, fun) |> Multi.run(:two, fun)
    rhs = Multi.new() |> Multi.run(:three, fun) |> Multi.run(:four, fun)

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
    fun   = fn _, _ -> {:ok, :ok} end
    multi = Multi.new() |> Multi.run(:run, fun)

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
      Multi.new()
      |> Multi.insert(:insert, changeset)
      |> Multi.insert({:insert, 1}, changeset)
      |> Multi.insert({:insert, 2}, changeset)
      |> Multi.run(:run, fn _repo, changes -> {:ok, changes} end)
      |> Multi.update(:update, changeset)
      |> Multi.delete(:delete, changeset)
      |> Multi.insert_all(:insert_all, Comment, [[x: 1]])
      |> Multi.update_all(:update_all, Comment, set: [x: 1])
      |> Multi.delete_all(:delete_all, Comment)
      |> Multi.delete_all({:delete_all, 1}, Comment)
      |> Multi.delete_all({:delete_all, 2}, Comment)

    assert [
      {:insert,          {:insert, _, []}},
      {{:insert, 1},     {:insert, _, []}},
      {{:insert, 2},     {:insert, _, []}},
      {:run,             {:run, _}},
      {:update,          {:update, _, []}},
      {:delete,          {:delete, _, []}},
      {:insert_all,      {:insert_all, _, _, []}},
      {:update_all,      {:update_all, _, _, []}},
      {:delete_all,      {:delete_all, _, []}},
      {{:delete_all, 1}, {:delete_all, _, []}},
      {{:delete_all, 2}, {:delete_all, _, []}},
    ] = Ecto.Multi.to_list(multi)
  end

  test "put" do
    name = :halo
    value = "statue"

    multi =
      Multi.new()
      |> Multi.put(name, value)

    assert multi.names == MapSet.new([name])
    assert multi.operations == [{name, {:put, value}}]
  end

  test "add changeset with invalid action" do
    changeset = %{Changeset.change(%Comment{}) | action: :invalid}

    assert_raise ArgumentError, ~r"an action already set to :invalid", fn ->
      Multi.new() |> Multi.insert(:changeset, changeset)
    end
  end

  test "add changeset with duplicate action" do
    changeset = %{Changeset.change(%Comment{}) | action: :insert}
    multi = Multi.new() |> Multi.insert(:changeset, changeset)

    assert multi.operations == [{:changeset, {:changeset, changeset, []}}]
  end

  test "add run with invalid arity" do
    assert_raise FunctionClauseError, fn ->
      Multi.new() |> Multi.run(:run, fn -> nil end)
    end
  end

  test "repeating an operation" do
    fun = fn _, _ -> {:ok, :ok} end
    assert_raise RuntimeError, ~r":run is already a member", fn ->
      Multi.new() |> Multi.run(:run, fun) |> Multi.run(:run, fun)
    end
  end

  describe "merge/2" do
    test "with fun" do
      changeset = Changeset.change(%Comment{})
      multi =
        Multi.new()
        |> Multi.insert(:insert, changeset)
        |> Multi.merge(fn data ->
          Multi.new() |> Multi.update(:update, Changeset.change(data.insert))
        end)

      assert {:ok, data} = TestRepo.transaction(multi)
      assert %Comment{} = data.insert
      assert %Comment{} = data.update
    end

    test "with mfa" do
      changeset = Changeset.change(%Comment{})
      multi =
        Multi.new()
        |> Multi.insert(:insert, changeset)
        |> Multi.merge(__MODULE__, :multi, [])

      assert {:ok, data} = TestRepo.transaction(multi)
      assert %Comment{} = data.insert
      assert %Comment{} = data.update
    end

    test "rollbacks on errors" do
      error = fn _, _ -> {:error, :error} end
      ok    = fn _, _ -> {:ok, :ok} end

      multi =
        Multi.new()
        |> Multi.run(:outside_ok, ok)
        |> Multi.merge(fn _ ->
          Multi.new()
          |> Multi.run(:inside_ok, ok)
          |> Multi.run(:inside_error, error)
        end)
        |> Multi.run(:outside_error, error)

      assert {:error, :inside_error, :error, data} = TestRepo.transaction(multi)
      assert :ok == data.outside_ok
      assert :ok == data.inside_ok
    end

    test "rollbacks on errors in nested function" do
      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.run(:foo, fn repo, _ ->
          repo.rollback(:bar)
        end)

      assert_raise RuntimeError, ~r"operation :bar is manually rolling back, which is not supported by Ecto.Multi", fn ->
        TestRepo.transaction(multi)
      end
    end

    test "does not allow repeated operations" do
      fun = fn _, _ -> {:ok, :ok} end

      multi =
        Multi.new()
        |> Multi.merge(fn _ ->
          Multi.new() |> Multi.run(:run, fun)
        end)
        |> Multi.run(:run, fun)

      assert_raise RuntimeError, ~r"found in both Ecto.Multi: \[:run\]", fn ->
        TestRepo.transaction(multi)
      end

      multi =
        Multi.new()
        |> Multi.merge(fn _ -> Multi.new() |> Multi.run(:run, fun) end)
        |> Multi.merge(fn _ -> Multi.new() |> Multi.run(:run, fun) end)

      assert_raise RuntimeError, ~r"found in both Ecto.Multi: \[:run\]", fn ->
        TestRepo.transaction(multi)
      end
    end
  end

  describe "Repo.transaction" do
    test "on success" do
      changeset = Changeset.change(%Comment{id: 1}, x: 1)
      multi =
        Multi.new()
        |> Multi.put(:put, 1)
        |> Multi.insert(:insert, changeset)
        |> Multi.run(:run, fn _repo, %{put: 1} = changes -> {:ok, changes} end)
        |> Multi.update(:update, changeset)
        |> Multi.update(:update_fun, fn _changes -> changeset end)
        |> Multi.delete(:delete, changeset)
        |> Multi.insert_all(:insert_all, Comment, [[x: 1]])
        |> Multi.update_all(:update_all, Comment, set: [x: 1])
        |> Multi.delete_all(:delete_all, Comment)

      assert {:ok, changes} = TestRepo.transaction(multi)
      assert_received {:transaction, _}
      assert {:messages, [
        {:insert, %{source: "comments"}},
        {:update, %{source: "comments"}},
        {:update, %{source: "comments"}},
        {:delete, %{source: "comments"}},
        {:insert_all, %{source: "comments"}, [[x: 1]]},
        {:update_all, %{from: %{source: {"comments", _}}}},
        {:delete_all, %{from: %{source: {"comments", _}}}}
      ]} = Process.info(self(), :messages)

      assert %Comment{} = changes.insert
      assert %Comment{} = changes.update
      assert %Comment{} = changes.update_fun
      assert %Comment{} = changes.delete
      assert {1, nil}   = changes.insert_all
      assert {1, nil}   = changes.update_all
      assert {1, nil}   = changes.delete_all
      assert Map.has_key?(changes.run, :insert)
      refute Map.has_key?(changes.run, :update)
    end

    test "with inspect" do
      import ExUnit.CaptureIO

      multi =
        Multi.new()
        |> Multi.inspect()
        |> Multi.put(:put, 1)
        |> Multi.put(:put2, 1)
        |> Multi.inspect(only: [:put])
        |> Multi.inspect(only: :put2)

      assert capture_io(fn ->
        assert {:ok, result} = TestRepo.transaction(multi)
        refute Map.has_key?(result, :before_put)
        refute Map.has_key?(result, :after_put)
      end) == "%{}\n%{put: 1}\n%{put2: 1}\n"
    end

    test "with empty multi" do
      assert {:ok, changes} = TestRepo.transaction(Multi.new())
      refute_received {:transaction, _}
      assert changes == %{}
    end

    test "rolls back from run" do
      changeset = Changeset.change(%Comment{id: 1}, x: 1)
      multi =
        Multi.new()
        |> Multi.insert(:insert, changeset)
        |> Multi.run(:run, fn _repo, _changes -> {:error, "error from run"} end)
        |> Multi.update(:update, changeset)
        |> Multi.delete(:delete, changeset)

      assert {:error, :run, "error from run", changes} = TestRepo.transaction(multi)
      assert_received {:transaction, _}
      assert_received {:rollback, _}
      assert {:messages, [{:insert, %{source: "comments"}}]} = Process.info(self(), :messages)
      assert %Comment{} = changes.insert
      refute Map.has_key?(changes, :run)
      refute Map.has_key?(changes, :update)
    end

    test "rolls back from repo" do
      changeset = Changeset.change(%Comment{id: 1}, x: 1)
      invalid   = put_in(changeset.data.__meta__.context, {:invalid, [unique: "comments_x_index"]})
                  |> Changeset.unique_constraint(:x)

      multi =
        Multi.new()
        |> Multi.insert(:insert, changeset)
        |> Multi.run(:run, fn _repo, _changes -> {:ok, "ok"} end)
        |> Multi.update(:update, invalid)
        |> Multi.delete(:delete, changeset)

      assert {:error, :update, error, changes} = TestRepo.transaction(multi)
      assert_received {:transaction, _}
      assert_received {:rollback, _}
      assert {:messages, [{:insert, %{source: "comments"}}]} = Process.info(self(), :messages)
      assert %Comment{} = changes.insert
      assert "ok" == changes.run
      assert error.errors == [x: {"has already been taken", [constraint: :unique, constraint_name: "comments_x_index"]}]
      refute Map.has_key?(changes, :update)
    end

    test "checks invalid changesets before starting transaction" do
      changeset = %{Changeset.change(%Comment{}) | valid?: false}
      multi = Multi.new() |> Multi.insert(:invalid, changeset)

      assert {:error, :invalid, invalid, %{}} = TestRepo.transaction(multi)
      assert invalid.data == changeset.data
      refute_received {:transaction, _}
    end

    test "checks error operation before starting transaction" do
      multi = Multi.new() |> Multi.error(:invalid, "error")

      assert {:error, :invalid, "error", %{}} = TestRepo.transaction(multi)
      refute_received {:transaction, _}
    end
  end

  describe "Multi.run receives the repo module as the first argument" do
    test "with anonymous functions" do
      fun = fn repo, _changes -> {:ok, repo} end
      multi = Multi.new() |> Multi.run(:run, fun)
      assert {:ok, changes} = TestRepo.transaction(multi)
      assert changes.run == TestRepo
    end

    test "with mfa functions" do
      multi = Multi.new() |> Multi.run(:run, __MODULE__, :run_ok, [])
      assert {:ok, changes} = TestRepo.transaction(multi)
      assert changes.run == TestRepo
    end

    test "raises on invalid return" do
      fun = fn _repo, _changes -> :invalid end
      multi = Multi.new() |> Multi.run(:run, fun)

      assert_raise RuntimeError, ~r"to return either {:ok, value} or {:error, value}", fn ->
        TestRepo.transaction(multi)
      end
    end
  end
end
