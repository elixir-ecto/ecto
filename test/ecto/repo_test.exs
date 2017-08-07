defmodule Ecto.RepoTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto, only: [put_meta: 2]
  require Ecto.TestRepo, as: TestRepo

  defmodule MySchema do
    use Ecto.Schema

    schema "my_schema" do
      field :x, :string
      field :y, :binary, source: :yyy
      field :z, :string, default: "z"
      field :array, {:array, :string}
      field :map, {:map, :string}
      belongs_to :another, MySchema.Another
    end
  end

  defmodule MySchemaNoPK do
    use Ecto.Schema

    @primary_key false
    schema "my_schema" do
      field :x, :string
    end
  end

  test "defines child_spec/1" do
    assert TestRepo.child_spec([]) == %{
      id: TestRepo,
      start: {TestRepo, :start_link, [[]]},
      type: :supervisor
    }
  end

  test "needs schema with primary key field" do
    schema = %MySchemaNoPK{x: "abc"}

    assert_raise Ecto.NoPrimaryKeyFieldError, fn ->
      TestRepo.update!(schema |> Ecto.Changeset.change, force: true)
    end

    assert_raise Ecto.NoPrimaryKeyFieldError, fn ->
      TestRepo.delete!(schema)
    end
  end

  test "works with primary key value" do
    schema = %MySchema{id: 1, x: "abc"}
    TestRepo.get(MySchema, 123)
    TestRepo.get_by(MySchema, x: "abc")
    TestRepo.update!(schema |> Ecto.Changeset.change, force: true)
    TestRepo.delete!(schema)
  end

  test "works with custom source schema" do
    schema = %MySchema{id: 1, x: "abc"} |> put_meta(source: "custom_schema")
    TestRepo.update!(schema |> Ecto.Changeset.change, force: true)
    TestRepo.delete!(schema)

    to_insert = %MySchema{x: "abc"} |> put_meta(source: "custom_schema")
    TestRepo.insert!(to_insert)
  end

  test "fails without primary key value" do
    schema = %MySchema{x: "abc"}

    assert_raise Ecto.NoPrimaryKeyValueError, fn ->
      TestRepo.update!(schema |> Ecto.Changeset.change, force: true)
    end

    assert_raise Ecto.NoPrimaryKeyValueError, fn ->
      schema
      |> Ecto.Changeset.change()
      |> TestRepo.update()
    end

    assert_raise Ecto.NoPrimaryKeyValueError, fn ->
      TestRepo.delete!(schema)
    end
  end

  test "validates schema types" do
    schema = %MySchema{x: 123}

    assert_raise Ecto.ChangeError, fn ->
      TestRepo.insert!(schema)
    end
  end

  test "validates get" do
    TestRepo.get(MySchema, 123)

    message = "cannot perform Ecto.TestRepo.get/2 because the given value is nil"
    assert_raise ArgumentError, message, fn ->
      TestRepo.get(MySchema, nil)
    end

    message = ~r"value `:atom` in `where` cannot be cast to type :id in query"
    assert_raise Ecto.Query.CastError, message, fn ->
      TestRepo.get(MySchema, :atom)
    end

    message = ~r"expected a from expression with a schema in query"
    assert_raise Ecto.QueryError, message, fn ->
      TestRepo.get(%Ecto.Query{}, :atom)
    end
  end

  test "validates get_by" do
    TestRepo.get_by(MySchema, id: 123)
    TestRepo.get_by(MySchema, %{id: 123})
    TestRepo.get_by(MySchema, id: nil)

    message = ~r"value `:atom` in `where` cannot be cast to type :id in query"
    assert_raise Ecto.Query.CastError, message, fn ->
      TestRepo.get_by(MySchema, id: :atom)
    end
  end

  test "stream emits row values lazily" do
    stream = TestRepo.stream(MySchema)
    refute_received :stream_execute
    assert Enum.to_list(stream) == [1]
    assert_received :stream_execute
    assert Enum.take(stream, 0) == []
    refute_received :stream_execute
  end

  test "validates update_all" do
    # Success
    TestRepo.update_all(MySchema, set: [x: "321"])

    query = from(e in MySchema, where: e.x == "123", update: [set: [x: "321"]])
    TestRepo.update_all(query, [])

    # Failures
    assert_raise ArgumentError, ~r/:returning expects at least one field to be given/, fn ->
      TestRepo.update_all MySchema, [set: [x: "321"]], returning: []
    end

    assert_raise Ecto.QueryError, fn ->
      TestRepo.update_all from(e in MySchema, select: e), set: [x: "321"]
    end

    assert_raise Ecto.QueryError, fn ->
      TestRepo.update_all from(e in MySchema, order_by: e.x), set: [x: "321"]
    end
  end

  test "validates delete_all" do
    # Success
    TestRepo.delete_all(MySchema)

    query = from(e in MySchema, where: e.x == "123")
    TestRepo.delete_all(query)

    # Failures
    assert_raise ArgumentError, ~r/:returning expects at least one field to be given/, fn ->
      TestRepo.delete_all MySchema, returning: []
    end

    assert_raise Ecto.QueryError, fn ->
      TestRepo.delete_all from(e in MySchema, select: e)
    end

    assert_raise Ecto.QueryError, fn ->
      TestRepo.delete_all from(e in MySchema, order_by: e.x)
    end
  end

  ## Changesets

  test "insert, update, insert_or_update and delete accepts changesets" do
    valid = Ecto.Changeset.cast(%MySchema{id: 1}, %{}, [])
    assert {:ok, %MySchema{}} = TestRepo.insert(valid)
    assert {:ok, %MySchema{}} = TestRepo.update(valid)
    assert {:ok, %MySchema{}} = TestRepo.insert_or_update(valid)
    assert {:ok, %MySchema{}} = TestRepo.delete(valid)
  end

  test "insert, update, insert_or_update and delete sets schema prefix" do
    valid = Ecto.Changeset.cast(%MySchema{id: 1}, %{x: "foo"}, [:x])

    assert {:ok, schema} = TestRepo.insert(valid, prefix: "public")
    {schema_prefix, _} = schema.__meta__.source
    assert schema_prefix == "public"

    assert {:ok, schema} = TestRepo.update(valid, prefix: "public")
    {schema_prefix, _} = schema.__meta__.source
    assert schema_prefix == "public"

    assert {:ok, schema} = TestRepo.delete(valid, prefix: "public")
    {schema_prefix, _} = schema.__meta__.source
    assert schema_prefix == "public"
  end

  test "insert, update, and delete sets schema prefix from changeset repo opts" do
    valid =
      %MySchema{id: 1}
      |> Ecto.Changeset.cast(%{x: "foo"}, [:x])
      |> Map.put(:repo_opts, [prefix: "public"])

    assert {:ok, schema} = TestRepo.insert(valid, prefix: "public")
    {schema_prefix, _} = schema.__meta__.source
    assert schema_prefix == "public"

    assert {:ok, schema} = TestRepo.update(valid, prefix: "public")
    {schema_prefix, _} = schema.__meta__.source
    assert schema_prefix == "public"

    assert {:ok, schema} = TestRepo.delete(valid, prefix: "public")
    {schema_prefix, _} = schema.__meta__.source
    assert schema_prefix == "public"
  end

  test "insert, update, insert_or_update and delete errors on invalid changeset" do
    invalid = %Ecto.Changeset{valid?: false, data: %MySchema{}}

    insert = %{invalid | action: :insert, repo: TestRepo}
    assert {:error, ^insert} = TestRepo.insert(invalid)
    assert {:error, ^insert} = TestRepo.insert_or_update(invalid)

    update = %{invalid | action: :update, repo: TestRepo}
    assert {:error, ^update} = TestRepo.update(invalid)

    delete = %{invalid | action: :delete, repo: TestRepo}
    assert {:error, ^delete} = TestRepo.delete(invalid)

    ignore = %{invalid | action: :ignore, repo: TestRepo}
    assert {:error, ^insert} = TestRepo.insert(ignore)
    assert {:error, ^update} = TestRepo.update(ignore)
    assert {:error, ^delete} = TestRepo.delete(ignore)

    assert_raise ArgumentError, ~r"a valid changeset with action :ignore was given to Ecto.TestRepo.insert/2", fn ->
      TestRepo.insert(%{ignore | valid?: true})
    end
  end

  test "insert!, update! and delete! accepts changesets" do
    valid = Ecto.Changeset.cast(%MySchema{id: 1}, %{}, [])
    assert %MySchema{} = TestRepo.insert!(valid)
    assert %MySchema{} = TestRepo.update!(valid)
    assert %MySchema{} = TestRepo.insert_or_update!(valid)
    assert %MySchema{} = TestRepo.delete!(valid)
  end

  test "insert!, update!, insert_or_update! and delete! fail on invalid changeset" do
    invalid = %Ecto.Changeset{valid?: false, data: %MySchema{}, types: %{}}

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

  test "insert!, update! and delete! fail on changeset without data" do
    invalid = %Ecto.Changeset{valid?: true, data: nil}

    assert_raise ArgumentError, "cannot insert a changeset without :data", fn ->
      TestRepo.insert!(invalid)
    end

    assert_raise ArgumentError, "cannot update a changeset without :data", fn ->
      TestRepo.update!(invalid)
    end

    assert_raise ArgumentError, "cannot delete a changeset without :data", fn ->
      TestRepo.delete!(invalid)
    end
  end

  test "insert!, update!, insert_or_update! and delete! fail on changeset with wrong action" do
    invalid = %Ecto.Changeset{valid?: true, data: %MySchema{id: 123}, action: :other}

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
    built  = Ecto.Changeset.cast(%MySchema{y: "built"}, %{}, [])
    loaded =
      %MySchema{y: "loaded"}
      |> TestRepo.insert!
      |> Ecto.Changeset.cast(%{y: "updated"}, [:y])
    assert_received {:insert, _}

    TestRepo.insert_or_update built
    assert_received {:insert, _}

    TestRepo.insert_or_update loaded
    assert_received {:update, _}
  end

  test "insert_or_update fails on invalid states" do
    deleted =
      %MySchema{y: "deleted"}
      |> TestRepo.insert!
      |> TestRepo.delete!
      |> Ecto.Changeset.cast(%{y: "updated"}, [:y])

    assert_raise ArgumentError, ~r/the changeset has an invalid state/, fn ->
      TestRepo.insert_or_update deleted
    end
  end

  test "insert_or_update fails when being passed a struct" do
    assert_raise ArgumentError, ~r/giving a struct to .* is not supported/, fn ->
      TestRepo.insert_or_update %MySchema{}
    end
  end

  defp prepare_changeset() do
    %MySchema{id: 1}
    |> Ecto.Changeset.cast(%{x: "one"}, [:x])
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

  describe "changeset constraints" do
    test "are mapped to repo constraint violations" do
      my_schema = %MySchema{id: 1}
      changeset =
        put_in(my_schema.__meta__.context, {:invalid, [unique: "custom_foo_index"]})
        |> Ecto.Changeset.change(x: "foo")
        |> Ecto.Changeset.unique_constraint(:foo, name: "custom_foo_index")
      assert {:error, changeset} = TestRepo.insert(changeset)
      refute changeset.valid?
    end

    test "are mapped to repo constraint violation using suffix match" do
      my_schema = %MySchema{id: 1}
      changeset =
        put_in(my_schema.__meta__.context, {:invalid, [unique: "foo_table_custom_foo_index"]})
        |> Ecto.Changeset.change(x: "foo")
        |> Ecto.Changeset.unique_constraint(:foo, name: "custom_foo_index", match: :suffix)
      assert {:error, changeset} = TestRepo.insert(changeset)
      refute changeset.valid?
    end

    test "are mapped to repo constraint violation using prefix match" do
      my_schema = %MySchema{id: 1}
      changeset =
        put_in(my_schema.__meta__.context, {:invalid, [unique: "foo_table_custom_foo_index"]})
        |> Ecto.Changeset.change(x: "foo")
        |> Ecto.Changeset.unique_constraint(:foo, name: "foo_table_custom_foo", match: :prefix)
      assert {:error, changeset} = TestRepo.insert(changeset)
      refute changeset.valid?
    end

    test "may fail to map to repo constraint violation on name" do
      my_schema = %MySchema{id: 1}
      changeset =
        put_in(my_schema.__meta__.context, {:invalid, [unique: "foo_table_custom_foo_index"]})
        |> Ecto.Changeset.change(x: "foo")
        |> Ecto.Changeset.unique_constraint(:foo, name: "custom_foo_index")
      assert_raise Ecto.ConstraintError, fn ->
        TestRepo.insert(changeset)
      end
    end

    test "may fail to map to repo constraint violation on index type" do
      my_schema = %MySchema{id: 1}
      changeset =
        put_in(my_schema.__meta__.context, {:invalid, [invalid_constraint_type: "my_schema_foo_index"]})
        |> Ecto.Changeset.change(x: "foo")
        |> Ecto.Changeset.unique_constraint(:foo)
      assert_raise Ecto.ConstraintError, fn ->
        TestRepo.insert(changeset)
      end
    end
  end

  describe "on conflict" do
    test "raises on unknown on_conflict value" do
      assert_raise ArgumentError, "unknown value for :on_conflict, got: :who_knows", fn ->
        TestRepo.insert(%MySchema{id: 1}, on_conflict: :who_knows)
      end
    end

    test "raises on non-empty conflict_target with on_conflict raise" do
      assert_raise ArgumentError, ":conflict_target option is forbidden when :on_conflict is :raise", fn ->
        TestRepo.insert(%MySchema{id: 1}, on_conflict: :raise, conflict_target: [:id])
      end
    end

    test "raises on query mismatch" do
      assert_raise ArgumentError, ~r"cannot run on_conflict: query", fn ->
        query = from p in "posts"
        TestRepo.insert(%MySchema{id: 1}, on_conflict: query)
      end
    end
  end

  describe "preload" do
    test "if first argument of preload is nil, it should return nil" do
      assert TestRepo.preload(nil, []) == nil
    end
  end

  describe "insert_all" do
    test "raises when on associations" do
      assert_raise ArgumentError, fn ->
        TestRepo.insert_all MySchema, [%{another: nil}]
      end
    end
  end

  test "load/2" do
    # string fields
    assert %MySchema{x: "abc"} =
           TestRepo.load(MySchema, %{"x" => "abc"})

    # atom fields
    assert %MySchema{x: "abc"} =
           TestRepo.load(MySchema, %{x: "abc"})

    # keyword list
    assert %MySchema{x: "abc"} =
           TestRepo.load(MySchema, [x: "abc"])

    # atom fields and values
    assert %MySchema{x: "abc"} =
           TestRepo.load(MySchema, {[:x], ["abc"]})

    # string fields and values
    assert %MySchema{x: "abc"} =
           TestRepo.load(MySchema, {["x"], ["abc"]})

    # default value
    assert %MySchema{x: "abc", z: "z"} =
           TestRepo.load(MySchema, %{x: "abc"})

    # source field
    assert %MySchema{y: "abc"} =
           TestRepo.load(MySchema, %{yyy: "abc"})

    # array field
    assert %MySchema{array: ["one", "two"]} =
           TestRepo.load(MySchema, %{array: ["one", "two"]})

    # map field with atoms
    assert %MySchema{map: %{color: "red"}} =
           TestRepo.load(MySchema, %{map: %{color: "red"}})

    # map field with strings
    assert %MySchema{map: %{"color" => "red"}} =
           TestRepo.load(MySchema, %{map: %{"color" => "red"}})

    # nil
    assert %MySchema{x: nil} =
           TestRepo.load(MySchema, %{x: nil})

    # invalid field is ignored
    assert %MySchema{} =
           TestRepo.load(MySchema, %{bad: "bad"})

    # invalid value
    assert_raise ArgumentError, "cannot load `0` as type :string for field `x` in schema Ecto.RepoTest.MySchema", fn ->
      TestRepo.load(MySchema, %{x: 0})
    end

    # schemaless
    assert TestRepo.load(%{x: :string}, %{x: "abc", bad: "bad"}) ==
           %{x: "abc"}
  end

  defmodule NoTransactionAdapter do
    defmacro __before_compile__(_opts), do: :ok
  end

  defmodule NoTransactionRepo do
    use Ecto.Repo, otp_app: :ecto, adapter: NoTransactionAdapter
  end

  test "no transaction functions generated on repo, without adapter support" do
    refute function_exported?(NoTransactionRepo, :transaction, 2)
    refute function_exported?(NoTransactionRepo, :in_transaction?, 2)
    refute function_exported?(NoTransactionRepo, :rollback, 1)
  end
end
