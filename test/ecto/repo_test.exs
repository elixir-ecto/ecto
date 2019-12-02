defmodule Ecto.RepoTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto, only: [put_meta: 2]
  require Ecto.TestRepo, as: TestRepo

  defmodule MyParent do
    use Ecto.Schema

    @schema_prefix "private"

    schema "my_parent" do
      field :n, :integer
    end

    def changeset(struct, params) do
      Ecto.Changeset.cast(struct, params, [:n])
    end
  end

  defmodule MyEmbed do
    use Ecto.Schema

    embedded_schema do
      field :x, :string
    end
  end

  defmodule MySchema do
    use Ecto.Schema

    schema "my_schema" do
      field :x, :string
      field :y, :binary, source: :yyy
      field :z, :string, default: "z"
      field :w, :string, virtual: true
      field :array, {:array, :string}
      field :map, {:map, :string}
    end
  end

  defmodule MySchemaWithPrefix do
    use Ecto.Schema

    @schema_prefix "private"

    schema "my_schema" do
      field :x, :string
    end
  end

  defmodule MySchemaWithAssoc do
    use Ecto.Schema

    schema "my_schema" do
      field :n, :integer
      belongs_to :parent, MyParent
    end
  end

  defmodule MySchemaWithEmbed do
    use Ecto.Schema

    schema "my_schema" do
      field :x, :string
      embeds_many :embeds, MyEmbed
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

  describe "get" do
    test "raises on bad inputs" do
      TestRepo.get(MySchema, 123)

      message = "cannot perform Ecto.Repo.get/2 because the given value is nil"
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
  end

  describe "get_by" do
    test "raises on bad inputs" do
      TestRepo.get_by(MySchema, id: 123)
      TestRepo.get_by(MySchema, %{id: 123})

      message = ~r"value `:atom` in `where` cannot be cast to type :id in query"
      assert_raise Ecto.Query.CastError, message, fn ->
        TestRepo.get_by(MySchema, id: :atom)
      end
    end
  end

  describe "aggregate" do
    test "aggregates on the given field" do
      TestRepo.aggregate(MySchema, :min, :id)
      assert_received {:all, query}
      assert inspect(query) == "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, select: min(m0.id)>"

      TestRepo.aggregate(MySchema, :max, :id)
      assert_received {:all, query}
      assert inspect(query) == "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, select: max(m0.id)>"

      TestRepo.aggregate(MySchema, :sum, :id)
      assert_received {:all, query}
      assert inspect(query) == "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, select: sum(m0.id)>"

      TestRepo.aggregate(MySchema, :avg, :id)
      assert_received {:all, query}
      assert inspect(query) == "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, select: avg(m0.id)>"

      TestRepo.aggregate(MySchema, :count, :id)
      assert_received {:all, query}
      assert inspect(query) == "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, select: count(m0.id)>"

      TestRepo.aggregate(MySchema, :count)
      assert_received {:all, query}
      assert inspect(query) == "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, select: count()>"
    end

    test "aggregates handle a prefix option" do
      TestRepo.aggregate(MySchema, :min, :id, prefix: "public")
      assert_received {:all, query}
      assert query.prefix == "public"
    end

    test "removes any preload from query" do
      from(MySchemaWithAssoc, preload: :parent) |> TestRepo.aggregate(:count, :id)
      assert_received {:all, query}
      assert inspect(query) == "#Ecto.Query<from m0 in Ecto.RepoTest.MySchemaWithAssoc, select: count(m0.id)>"
    end

    test "removes order by from query without distinct/limit/offset" do
      from(MySchema, order_by: :id) |> TestRepo.aggregate(:count, :id)
      assert_received {:all, query}
      assert inspect(query) == "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, select: count(m0.id)>"
    end

    test "overrides any select" do
      from(MySchema, select: true) |> TestRepo.aggregate(:count, :id)
      assert_received {:all, query}
      assert inspect(query) == "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, select: count(m0.id)>"
    end

    test "uses subqueries with distinct/limit/offset" do
      from(MySchema, limit: 5) |> TestRepo.aggregate(:count, :id)
      assert_received {:all, query}
      assert inspect(query) ==
               "#Ecto.Query<from m0 in subquery(from m0 in Ecto.RepoTest.MySchema,\n" <>
                "  limit: 5,\n" <>
                "  select: %{id: m0.id}), select: count(m0.id)>"
    end

    test "raises when aggregating with group_by" do
      assert_raise Ecto.QueryError, ~r"cannot aggregate on query with group_by", fn ->
        from(MySchema, group_by: [:id]) |> TestRepo.aggregate(:count, :id)
      end
    end
  end

  describe "exists?" do
    test "selects 1 and sets limit to 1" do
      TestRepo.exists?(MySchema)
      assert_received {:all, query}
      assert inspect(query) == "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, limit: 1, select: 1>"

      from(MySchema, select: [:id], limit: 10) |> TestRepo.exists?
      assert_received {:all, query}
      assert inspect(query) == "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, limit: 1, select: 1>"
    end

    test "removes any preload from query" do
      from(MySchemaWithAssoc, preload: :parent) |> TestRepo.exists?
      assert_received {:all, query}
      assert inspect(query) == "#Ecto.Query<from m0 in Ecto.RepoTest.MySchemaWithAssoc, limit: 1, select: 1>"
    end

    test "removes distinct from query" do
      from(MySchema, select: [:id], distinct: true) |> TestRepo.exists?
      assert_received {:all, query}
      assert inspect(query) == "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, limit: 1, select: 1>"
    end

    test "removes order by from query without distinct/limit/offset" do
      from(MySchema, order_by: :id) |> TestRepo.exists?
      assert_received {:all, query}
      assert inspect(query) == "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, limit: 1, select: 1>"
    end

    test "overrides any select" do
      from(MySchema, select: true) |> TestRepo.exists?
      assert_received {:all, query}
      assert inspect(query) == "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, limit: 1, select: 1>"
    end
  end

  describe "stream" do
    test "emits row values lazily" do
      stream = TestRepo.stream(MySchema)
      refute_received {:stream, _}
      assert [%MySchema{id: 1}] = Enum.to_list(stream)
      assert_received {:stream, _}
      assert Enum.take(stream, 0) == []
      refute_received {:stream, _}
    end

    test "does not work with preloads" do
      query = from m in MySchemaWithAssoc, preload: [:parent]

      assert_raise Ecto.QueryError, ~r"preloads are not supported on streams", fn ->
        TestRepo.stream(query)
      end

      query =
        MySchemaWithAssoc
        |> join(:inner, [m], p in assoc(m, :parent))
        |> preload([_m, p], parent: p)

      assert_raise Ecto.QueryError, ~r"preloads are not supported on streams", fn ->
        TestRepo.stream(query)
      end
    end
  end

  test "insert with returning" do
    TestRepo.insert(%MySchemaWithAssoc{}, returning: [:id])
    assert_received {:insert, %{source: "my_schema", returning: [:id]}}
    TestRepo.insert(%MySchemaWithAssoc{}, returning: [:parent_id])
    assert_received {:insert, %{source: "my_schema", returning: [:id, :parent_id]}}
    TestRepo.insert(%MySchemaWithAssoc{}, returning: true)
    assert_received {:insert, %{source: "my_schema", returning: [:id, :parent_id, :n]}}
    TestRepo.insert(%MySchemaWithAssoc{}, returning: false)
    assert_received {:insert, %{source: "my_schema", returning: [:id]}}
  end

  test "update with returning" do
    changeset = Ecto.Changeset.change(%MySchemaWithAssoc{id: 1}, %{n: 2})
    TestRepo.update(changeset, returning: [:id])
    assert_received {:update, %{source: "my_schema", returning: [:id]}}
    TestRepo.update(changeset, returning: [:parent_id])
    assert_received {:update, %{source: "my_schema", returning: [:parent_id]}}
    TestRepo.update(changeset, returning: true)
    assert_received {:update, %{source: "my_schema", returning: [:parent_id, :n, :id]}}
    TestRepo.update(changeset, returning: false)
    assert_received {:update, %{source: "my_schema", returning: []}}
  end

  describe "insert_all" do
    test "takes query" do
      import Ecto.Query

      value = "foo"
      query = from(s in MySchema, select: s.x, where: s.y == ^value)

      TestRepo.insert_all(MySchema, [
        [y: "y1", x: "x1"],
        [x: query, z: "z2"],
        [z: "z3", x: query],
        [y: query, z: query]
      ])

      assert_received {:insert_all, %{source: "my_schema"}, rows}
      assert [[x: "x1", yyy: "y1"],
              [x: {%Ecto.Query{} = query2, [^value]}, z: "z2"],
              [x: {%Ecto.Query{} = query3, [^value]}, z: "z3"],
              [yyy: {%Ecto.Query{} = query4y, [^value]}, z: {%Ecto.Query{} = query4x, [^value]}]] = rows

      assert [%{expr: {:==, _, [_, {:^, [], [2]}]}}] = query2.wheres
      assert [%{expr: {:==, _, [_, {:^, [], [4]}]}}] = query3.wheres
      assert [%{expr: {:==, _, [_, {:^, [], [6]}]}}] = query4y.wheres
      assert [%{expr: {:==, _, [_, {:^, [], [7]}]}}] = query4x.wheres
    end

    test "raises when on associations" do
      assert_raise ArgumentError, fn ->
        TestRepo.insert_all MySchema, [%{another: nil}]
      end
    end
  end

  describe "update_all" do
    test "raises on bad input" do
      # Success
      TestRepo.update_all(MySchema, set: [x: "321"])

      query = from(e in MySchema, where: e.x == "123", update: [set: [x: "321"]])
      TestRepo.update_all(query, [])

      assert_raise Ecto.QueryError, fn ->
        TestRepo.update_all from(e in MySchema, order_by: e.x), set: [x: "321"]
      end
    end
  end

  describe "delete_all" do
    test "raises on bad inputs" do
      # Success
      TestRepo.delete_all(MySchema)

      query = from(e in MySchema, where: e.x == "123")
      TestRepo.delete_all(query)

      assert_raise Ecto.QueryError, fn ->
        TestRepo.delete_all from(e in MySchema, order_by: e.x)
      end
    end
  end

  describe "schema operations" do
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

    test "works with custom source schema" do
      schema = %MySchema{id: 1, x: "abc"} |> put_meta(source: "custom_schema")
      TestRepo.update!(schema |> Ecto.Changeset.change, force: true)
      TestRepo.delete!(schema)

      to_insert = %MySchema{x: "abc"} |> put_meta(source: "custom_schema")
      TestRepo.insert!(to_insert)
    end

    test "provides meaningful error messages on dump error" do
      defmodule DumpSchema do
        use Ecto.Schema

        schema "my_schema" do
          field :d, :decimal
          field :t, :time
          field :t_usec, :time_usec
          field :x, :string
        end
      end

      schema = struct(DumpSchema, x: 123)

      assert_raise Ecto.ChangeError, ~r"does not match type :string$", fn ->
        TestRepo.insert!(schema)
      end
    end
  end

  describe "changeset operations" do
    test "insert, update, insert_or_update and delete" do
      valid = Ecto.Changeset.cast(%MySchema{id: 1}, %{x: "foo"}, [:x])
      assert {:ok, %MySchema{}} = TestRepo.insert(valid)
      assert {:ok, %MySchema{}} = TestRepo.update(valid)
      assert {:ok, %MySchema{}} = TestRepo.insert_or_update(valid)
      assert {:ok, %MySchema{}} = TestRepo.delete(valid)
    end

    test "insert, update, insert_or_update and delete with virtual field" do
      valid = Ecto.Changeset.cast(%MySchema{id: 1}, %{w: "foo"}, [:w])
      assert {:ok, %MySchema{w: "foo"}} = TestRepo.insert(valid)
      assert {:ok, %MySchema{w: "foo"}} = TestRepo.update(valid)
      assert {:ok, %MySchema{w: "foo"}} = TestRepo.insert_or_update(valid)
      assert {:ok, %MySchema{w: "foo"}} = TestRepo.delete(valid)
    end

    test "insert, update, insert_or_update and delete filters out unknown field" do
      valid = Ecto.Changeset.change(%MySchema{id: 1})
      valid = put_in valid.changes[:unknown], "foo"

      assert {:ok, %MySchema{} = inserted} = TestRepo.insert(valid)
      refute Map.has_key?(inserted, :unknown)

      assert {:ok, %MySchema{} = updated} = TestRepo.update(valid)
      refute Map.has_key?(updated, :unknown)

      assert {:ok, %MySchema{} = upserted} = TestRepo.insert_or_update(valid)
      refute Map.has_key?(upserted, :unknown)

      assert {:ok, %MySchema{} = deleted} = TestRepo.delete(valid)
      refute Map.has_key?(deleted, :unknown)
    end

    test "insert, update, and delete raises on stale entries" do
      my_schema = %MySchema{id: 1}
      my_schema = put_in(my_schema.__meta__.context, {:error, :stale})
      stale = Ecto.Changeset.cast(my_schema, %{x: "foo"}, [:x])

      assert_raise Ecto.StaleEntryError, fn -> TestRepo.insert(stale) end
      assert_raise Ecto.StaleEntryError, fn -> TestRepo.update(stale) end
      assert_raise Ecto.StaleEntryError, fn -> TestRepo.delete(stale) end
    end

    test "insert, update, and delete adds error to stale error field" do
      my_schema = %MySchema{id: 1}
      my_schema = put_in(my_schema.__meta__.context, {:error, :stale})
      stale = Ecto.Changeset.cast(my_schema, %{x: "foo"}, [:x])

      assert {:error, changeset} = TestRepo.insert(stale, [stale_error_field: :id])
      assert changeset.errors == [id: {"is stale", [stale: true]}]

      assert {:error, changeset} = TestRepo.update(stale, [stale_error_field: :id])
      assert changeset.errors == [id: {"is stale", [stale: true]}]

      assert {:error, changeset} = TestRepo.delete(stale, [stale_error_field: :id])
      assert changeset.errors == [id: {"is stale", [stale: true]}]

      assert_raise Ecto.StaleEntryError, fn -> TestRepo.insert(stale, [stale_error_field: "id"]) end
    end

    test "insert, update, and delete adds custom stale error message" do
      my_schema = %MySchema{id: 1}
      my_schema = put_in(my_schema.__meta__.context, {:error, :stale})
      stale = Ecto.Changeset.cast(my_schema, %{x: "foo"}, [:x])

      options = [
        stale_error_field: :id,
        stale_error_message: "is old"
      ]

      assert {:error, changeset} = TestRepo.insert(stale, options)
      assert changeset.errors == [id: {"is old", [stale: true]}]

      assert {:error, changeset} = TestRepo.update(stale, options)
      assert changeset.errors == [id: {"is old", [stale: true]}]

      assert {:error, changeset} = TestRepo.delete(stale, options)
      assert changeset.errors == [id: {"is old", [stale: true]}]
    end

    test "get, get_by, one and all sets schema prefix" do
      assert schema = TestRepo.get(MySchema, 123, prefix: "public")
      assert schema.__meta__.prefix == "public"

      assert schema = TestRepo.get_by(MySchema, [id: 123], prefix: "public")
      assert schema.__meta__.prefix == "public"

      assert schema = TestRepo.one(MySchema, prefix: "public")
      assert schema.__meta__.prefix == "public"

      assert [schema] = TestRepo.all(MySchema, prefix: "public")
      assert schema.__meta__.prefix == "public"
    end

    test "get, get_by, one and all ignores prefix if schema_prefix set" do
      assert schema = TestRepo.get(MySchemaWithPrefix, 123, prefix: "public")
      assert schema.__meta__.prefix == "private"

      assert schema = TestRepo.get_by(MySchemaWithPrefix, [id: 123], prefix: "public")
      assert schema.__meta__.prefix == "private"

      assert schema = TestRepo.one(MySchemaWithPrefix, prefix: "public")
      assert schema.__meta__.prefix == "private"

      assert [schema] = TestRepo.all(MySchemaWithPrefix, prefix: "public")
      assert schema.__meta__.prefix == "private"
    end

    test "insert and delete sets schema prefix with struct" do
      valid = %MySchema{id: 1}

      assert {:ok, schema} = TestRepo.insert(valid, prefix: "public")
      assert schema.__meta__.prefix == "public"

      assert {:ok, schema} = TestRepo.delete(valid, prefix: "public")
      assert schema.__meta__.prefix == "public"
    end

    test "insert and delete prefix overrides schema_prefix with struct" do
      valid = %MySchemaWithPrefix{id: 1}

      assert {:ok, schema} = TestRepo.insert(valid, prefix: "public")
      assert schema.__meta__.prefix == "public"

      assert {:ok, schema} = TestRepo.delete(valid, prefix: "public")
      assert schema.__meta__.prefix == "public"
    end

    test "insert, update, insert_or_update and delete sets schema prefix with changeset" do
      valid = Ecto.Changeset.cast(%MySchema{id: 1}, %{x: "foo"}, [:x])

      assert {:ok, schema} = TestRepo.insert(valid, prefix: "public")
      assert schema.__meta__.prefix == "public"

      assert {:ok, schema} = TestRepo.insert_or_update(valid, prefix: "public")
      assert schema.__meta__.prefix == "public"

      assert {:ok, schema} = TestRepo.update(valid, prefix: "public")
      assert schema.__meta__.prefix == "public"

      assert {:ok, schema} = TestRepo.delete(valid, prefix: "public")
      assert schema.__meta__.prefix == "public"
    end

    test "insert, update, insert_or_update and delete prefix overrides schema_prefix" do
      valid = Ecto.Changeset.cast(%MySchemaWithPrefix{id: 1}, %{x: "foo"}, [:x])

      assert {:ok, schema} = TestRepo.insert(valid)
      assert schema.__meta__.prefix == "private"

      assert {:ok, schema} = TestRepo.insert(valid, prefix: "public")
      assert schema.__meta__.prefix == "public"

      assert {:ok, schema} = TestRepo.insert_or_update(valid, prefix: "public")
      assert schema.__meta__.prefix == "public"

      assert {:ok, schema} = TestRepo.update(valid, prefix: "public")
      assert schema.__meta__.prefix == "public"

      assert {:ok, schema} = TestRepo.delete(valid, prefix: "public")
      assert schema.__meta__.prefix == "public"
    end

    test "insert, update, and delete sets schema prefix from changeset repo opts" do
      valid =
        %MySchema{id: 1}
        |> Ecto.Changeset.cast(%{x: "foo"}, [:x])
        |> Map.put(:repo_opts, [prefix: "public"])

      assert {:ok, schema} = TestRepo.insert(valid)
      assert schema.__meta__.prefix == "public"

      assert {:ok, schema} = TestRepo.update(valid)
      assert schema.__meta__.prefix == "public"

      assert {:ok, schema} = TestRepo.delete(valid)
      assert schema.__meta__.prefix == "public"
    end

    test "insert, update, and delete prefix option overrides repo opts" do
      valid =
        %MySchema{id: 1}
        |> Ecto.Changeset.cast(%{x: "foo"}, [:x])
        |> Map.put(:repo_opts, [prefix: "public"])

      assert {:ok, schema} = TestRepo.insert(valid, prefix: "private")
      assert schema.__meta__.prefix == "private"

      assert {:ok, schema} = TestRepo.update(valid, prefix: "private")
      assert schema.__meta__.prefix == "private"

      assert {:ok, schema} = TestRepo.delete(valid, prefix: "private")
      assert schema.__meta__.prefix == "private"
    end

    test "insert, update and insert_or_update parent schema_prefix overrides children schema_prefix" do
      assert {:ok, schema} = TestRepo.insert(%MyParent{id: 1})
      assert schema.__meta__.prefix == "private"

      valid =
        %MySchemaWithAssoc{id: 1}
        |> TestRepo.preload(:parent)
        |> Ecto.Changeset.cast(%{parent: %{id: 1}}, [])
        |> Ecto.Changeset.cast_assoc(:parent)

      assert {:ok, schema} = TestRepo.insert(valid)
      assert schema.parent.__meta__.prefix == nil

      assert {:ok, schema} = TestRepo.insert_or_update(valid)
      assert schema.parent.__meta__.prefix == nil

      assert {:ok, schema} = TestRepo.update(valid)
      assert schema.parent.__meta__.prefix == nil
    end

    test "insert, update and insert_or_update prefix overrides schema_prefix in associations" do
      valid =
        %MySchemaWithAssoc{id: 1}
        |> TestRepo.preload(:parent)
        |> Ecto.Changeset.cast(%{parent: %{id: 1}}, [])
        |> Ecto.Changeset.cast_assoc(:parent)

      assert {:ok, schema} = TestRepo.insert(valid, prefix: "public")
      assert schema.parent.__meta__.prefix == "public"

      assert {:ok, schema} = TestRepo.insert_or_update(valid, prefix: "public")
      assert schema.parent.__meta__.prefix == "public"

      assert {:ok, schema} = TestRepo.update(valid, prefix: "public")
      assert schema.parent.__meta__.prefix == "public"
    end

    test "insert, and update prefix option overrides repo opts in associations" do
      valid =
        %MySchemaWithAssoc{id: 1}
        |> TestRepo.preload(:parent)
        |> Ecto.Changeset.cast(%{parent: %{n: 1}}, [])
        |> Ecto.Changeset.cast_assoc(:parent)

      valid = put_in(valid.changes.parent.repo_opts, [prefix: "public"])

      assert {:ok, schema} = TestRepo.insert(valid, prefix: "other")
      assert schema.parent.__meta__.prefix == "other"

      assert {:ok, schema} = TestRepo.update(valid, prefix: "other")
      assert schema.parent.__meta__.prefix == "other"
    end

    test "insert, update, insert_or_update and delete errors on invalid changeset" do
      invalid = %Ecto.Changeset{valid?: false, data: %MySchema{}}

      insert = %{invalid | action: :insert, repo: TestRepo, repo_opts: [prefix: "prefix"]}
      assert {:error, ^insert} = TestRepo.insert(invalid, prefix: "prefix")
      assert {:error, ^insert} = TestRepo.insert_or_update(invalid, prefix: "prefix")

      update = %{invalid | action: :update, repo: TestRepo, repo_opts: [prefix: "prefix"]}
      assert {:error, ^update} = TestRepo.update(invalid, prefix: "prefix")

      delete = %{invalid | action: :delete, repo: TestRepo, repo_opts: [prefix: "prefix"]}
      assert {:error, ^delete} = TestRepo.delete(invalid, prefix: "prefix")

      ignore = %{invalid | action: :ignore, repo: TestRepo, repo_opts: [prefix: "prefix"]}
      assert {:error, ^insert} = TestRepo.insert(ignore, prefix: "prefix")
      assert {:error, ^update} = TestRepo.update(ignore, prefix: "prefix")
      assert {:error, ^delete} = TestRepo.delete(ignore, prefix: "prefix")

      assert_raise ArgumentError, ~r"a valid changeset with action :ignore was given to Ecto.TestRepo.insert/2", fn ->
        TestRepo.insert(%{ignore | valid?: true})
      end
    end

    test "insert!, update!, insert_or_update! and delete!" do
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
  end

  describe "changeset prepare" do
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

    test "does not run transaction without prepare" do
      TestRepo.insert!(%MySchema{id: 1})
      refute_received {:transaction, _}
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

    test "on embeds" do
      embed_changeset =
        %MyEmbed{}
        |> Ecto.Changeset.cast(%{x: "one"}, [:x])
        |> Ecto.Changeset.prepare_changes(fn %{repo: repo} = changeset ->
          Process.put(:ecto_repo, repo)
          Process.put(:ecto_counter, 1)
          changeset
        end)
        |> Ecto.Changeset.prepare_changes(fn changeset ->
          1 = Process.get(:ecto_counter)
          Process.put(:ecto_counter, 2)
          Ecto.Changeset.update_change(changeset, :x, &String.upcase/1)
        end)

      changeset =
        %MySchemaWithEmbed{id: 1}
        |> Ecto.Changeset.cast(%{x: "one"}, [:x])
        |> Ecto.Changeset.put_embed(:embeds, [embed_changeset])

      %MySchemaWithEmbed{embeds: [embed]} = TestRepo.insert!(changeset)
      assert embed.x == "ONE"
      assert_received {:transaction, _}
      assert Process.get(:ecto_repo) == TestRepo
      assert Process.get(:ecto_counter) == 2
    end
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
    test "passes all fields on replace_all" do
      fields = [:id, :x, :yyy, :z, :array, :map]
      TestRepo.insert(%MySchema{id: 1}, on_conflict: :replace_all)
      assert_received {:insert, %{source: "my_schema", on_conflict: {^fields, [], []}}}
    end

    test "passes all fields+embeds on replace_all" do
      fields = [:id, :x, :embeds]
      TestRepo.insert(%MySchemaWithEmbed{id: 1}, on_conflict: :replace_all)
      assert_received {:insert, %{source: "my_schema", on_conflict: {^fields, [], []}}}
    end

    test "replaces specified fields on replace" do
      fields = [:x, :yyy]
      TestRepo.insert(
        %MySchema{id: 1},
        on_conflict: {:replace, [:x, :y]},
        conflict_target: [:id]
      )
      assert_received {:insert, %{source: "my_schema", on_conflict: {^fields, [], [:id]}}}
    end

    test "replaces specified fields on replace without a schema" do
      fields = [:x, :yyy]
      rows = [[id: 1, x: "x", yyy: "yyy"]]
      TestRepo.insert_all(
        "my_schema",
        rows,
        on_conflict: {:replace, [:x, :yyy]},
        conflict_target: [:id]
      )
      assert_received {:insert_all, %{source: "my_schema", on_conflict: {^fields, [], [:id]}}, ^rows}
    end

    test "raises on non-existent fields on replace" do
      assert_raise ArgumentError, "unknown field for :on_conflict, got: :unknown", fn ->
        TestRepo.insert(
          %MySchema{id: 1},
          on_conflict: {:replace, [:unknown]},
          conflict_target: [:id]
        )
      end
    end

    test "passes all fields except primary keys on replace_all_except_primary_keys" do
      fields = [:x, :yyy, :z, :array, :map]
      TestRepo.insert(%MySchema{id: 1}, on_conflict: :replace_all_except_primary_key)
      assert_received {:insert, %{source: "my_schema", on_conflict: {^fields, [], []}}}
    end

    test "converts keyword list into query" do
      TestRepo.insert(%MySchema{id: 1}, on_conflict: [set: [x: "123", y: "456"]])
      assert_received {:insert, %{source: "my_schema", on_conflict: {query, ["123", "456"], []}}}
      assert %Ecto.Query{} = query
      assert hd(query.updates).expr == [set: [x: {:^, [], [2]}, yyy: {:^, [], [3]}]]
    end

    test "does not pass on_conflict to children" do
      TestRepo.insert(%MySchemaWithAssoc{id: 1, parent: %MyParent{}}, on_conflict: :replace_all)
      assert_received {:insert, %{source: "my_schema", on_conflict: {_, _, _}}}
      assert_received {:insert, %{source: "my_parent", on_conflict: {:raise, _, _}}}
    end

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

    test "raises on empty conflict_target with on_conflict replace" do
      assert_raise ArgumentError, ":conflict_target option is required when :on_conflict is replace", fn ->
        TestRepo.insert(%MySchema{id: 1}, on_conflict: {:replace, []})
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
    test "returns nil if first argument of preload is nil" do
      assert TestRepo.preload(nil, []) == nil
    end
  end

  describe "checkout" do
    test "checks out a connection" do
      fun = fn -> :done end
      assert TestRepo.checkout(fun) == :done
      assert_received {:checkout, ^fun}
    end
  end

  describe "custom type as primary key" do
    defmodule PrefixedID do
      use Ecto.Type
      def type(), do: :binary_id
      def cast("foo-" <> _ = id), do: {:ok, id}
      def cast(id), do: {:ok, "foo-" <> id}
      def load(uuid), do: {:ok, "foo-" <> uuid}
      def dump("foo-" <> uuid), do: {:ok, uuid}
      def dump(_uuid), do: :error
    end

    defmodule MySchemaCustomPK do
      use Ecto.Schema

      @primary_key {:id, PrefixedID, autogenerate: true}
      schema "" do
      end
    end

    test "autogenerates value" do
      assert {:ok, inserted} = TestRepo.insert(%MySchemaCustomPK{})
      assert "foo-" <> _uuid = inserted.id
    end

    test "custom value" do
      id = "a92f6d0e-52ef-4df8-808b-32d8ef037d48"
      changeset = Ecto.Changeset.cast(%MySchemaCustomPK{}, %{id: id}, [:id])

      assert {:ok, inserted} = TestRepo.insert(changeset)
      assert inserted.id == "foo-" <> id
    end
  end

  describe "transactions" do
    defmodule NoTransactionAdapter do
      @behaviour Ecto.Adapter
      defmacro __before_compile__(_opts), do: :ok
      def dumpers(_, _), do: raise "not implemented"
      def loaders(_, _), do: raise "not implemented"
      def init(_), do: raise "not implemented"
      def checkout(_, _, _), do: raise "not implemented"
      def ensure_all_started(_, _), do: raise "not implemented"
    end

    defmodule NoTransactionRepo do
      use Ecto.Repo, otp_app: :ecto, adapter: NoTransactionAdapter
    end

    test "no transaction functions generated on repo without adapter support" do
      assert function_exported?(NoTransactionRepo, :config, 0)
      refute function_exported?(NoTransactionRepo, :transaction, 2)
      refute function_exported?(NoTransactionRepo, :in_transaction?, 2)
      refute function_exported?(NoTransactionRepo, :rollback, 1)
    end
  end

  describe "dynamic repo" do
    setup do
      {:ok, pid} = TestRepo.start_link(name: nil)
      TestRepo = TestRepo.put_dynamic_repo(pid)
      :ok
    end

    test "puts the dynamic repo in pdict" do
      assert is_pid TestRepo.get_dynamic_repo()

      assert Task.async(fn -> TestRepo.get_dynamic_repo() end) |> Task.await() ==
               TestRepo
    end

    test "keeps the proper repo in prepare_changes callback" do
      %MySchema{id: 1}
      |> Ecto.Changeset.cast(%{x: "one"}, [:x])
      |> Ecto.Changeset.prepare_changes(fn changeset ->
        Process.put(:ecto_prepared, true)
        assert changeset.repo == TestRepo
        changeset
      end)
      |> TestRepo.insert!()

      assert Process.get(:ecto_prepared)
    end

    test "keeps the proper repo in  multi" do
      fun = fn repo, _changes -> {:ok, repo} end
      multi = Ecto.Multi.new() |> Ecto.Multi.run(:run, fun)
      assert {:ok, changes} = TestRepo.transaction(multi)
      assert changes.run == TestRepo
    end

    test "accepts a default dynamic repo compile-time option" do
      defmodule CustomDynamicRepo do
        use Ecto.Repo, otp_app: :ecto, adapter: Ecto.TestAdapter, default_dynamic_repo: :other
      end

      assert CustomDynamicRepo.get_dynamic_repo() == :other
    end
  end

  describe "read-only repo" do
    test "accepts a read-only compile-time option" do
      defmodule ReadOnlyRepo do
        use Ecto.Repo, otp_app: :ecto, adapter: Ecto.TestAdapter, read_only: true
      end

      refute function_exported?(ReadOnlyRepo, :insert, 2)
      refute function_exported?(ReadOnlyRepo, :update, 2)
      refute function_exported?(ReadOnlyRepo, :delete, 2)
      refute function_exported?(ReadOnlyRepo, :insert_all, 3)
      refute function_exported?(ReadOnlyRepo, :update_all, 3)
      refute function_exported?(ReadOnlyRepo, :delete_all, 2)
    end
  end

  describe "prepare_for_query" do
    defmodule PrepareRepo do
      use Ecto.Repo, otp_app: :ecto, adapter: Ecto.TestAdapter

      def prepare_query(op, query, opts) do
        send(self(), {op, query, opts})
        {%{query | prefix: "rewritten"}, opts}
      end
    end

    setup do
      _ = PrepareRepo.start_link(url: "ecto://user:pass@local/hello")
      :ok
    end

    test "all" do
      query = from p in MyParent, select: p

      PrepareRepo.all(query, [hello: :world])
      assert_received {:all, ^query, [hello: :world]}
      assert_received {:all, %{prefix: "rewritten"}}

      PrepareRepo.one(query, [hello: :world])
      assert_received {:all, ^query, [hello: :world]}
      assert_received {:all, %{prefix: "rewritten"}}
    end

    test "update_all" do
      query = from p in MyParent, update: [set: [n: 1]]
      PrepareRepo.update_all(query, [], [hello: :world])
      assert_received {:update_all, ^query, [hello: :world]}
      assert_received {:update_all, %{prefix: "rewritten"}}
    end

    test "delete_all" do
      query = from p in MyParent
      PrepareRepo.delete_all(query, [hello: :world])
      assert_received {:delete_all, ^query, [hello: :world]}
      assert_received {:delete_all, %{prefix: "rewritten"}}
    end

    test "stream" do
      query = from p in MyParent, select: p
      PrepareRepo.stream(query, [hello: :world]) |> Enum.to_list()
      assert_received {:stream, ^query, [hello: :world]}
      assert_received {:stream, %{prefix: "rewritten"}}
    end
  end

  describe "transaction" do
    test "an arity zero function will be executed any it's value returned" do
      fun = fn -> :ok end
      assert {:ok, :ok} = TestRepo.transaction(fun)
      assert_received {:transaction, _}
    end

    test "an arity one function will be passed the repo as first argument" do
      fun = fn repo -> repo end

      assert {:ok, TestRepo} = TestRepo.transaction(fun)
      assert_received {:transaction, _}
    end
  end
end
