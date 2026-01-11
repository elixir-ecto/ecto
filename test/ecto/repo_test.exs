defmodule Ecto.RepoTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto, only: [put_meta: 2]
  alias Ecto.TestRepo

  defmodule MyParent do
    use Ecto.Schema

    schema "my_parent" do
      field :n, :integer
    end

    def changeset(struct, params) do
      Ecto.Changeset.cast(struct, params, [:n])
    end
  end

  defmodule MyParentWithPrefix do
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
      field :y, :string
    end

    def changeset(struct, params) do
      Ecto.Changeset.cast(struct, params, [:x])
    end
  end

  defmodule MySchemaChild do
    use Ecto.Schema

    schema "my_schema_child" do
      field :a, :string
      belongs_to :my_schema, MySchema
      belongs_to :my_schema_no_pk, MySchemaNoPK, references: :n, foreign_key: :n
    end

    def changeset(struct, params) do
      Ecto.Changeset.cast(struct, params, [:a])
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
      has_many :children, MySchemaChild
    end
  end

  defmodule MySchemaWithPrefix do
    use Ecto.Schema

    @schema_prefix "private"

    schema "my_schema" do
      field :x, :string
    end
  end

  defmodule MySchemaWithNonStringPrefix do
    use Ecto.Schema

    @schema_prefix %{key: :private}

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

  defmodule MySchemaWithMultiAssoc do
    use Ecto.Schema

    schema "my_schema" do
      field :n, :integer
      belongs_to :parent, MyParent
      belongs_to :mother, MyParent
    end
  end

  defmodule MySchemaWithPrefixedAssoc do
    use Ecto.Schema

    schema "my_schema" do
      field :n, :integer
      belongs_to :parent, MyParentWithPrefix
    end
  end

  defmodule MyPrefixedSchemaWithAssoc do
    use Ecto.Schema

    @schema_prefix "other"

    schema "my_schema" do
      field :n, :integer
      belongs_to :parent, MyParent
    end
  end

  defmodule MyPrefixedSchemaWithPrefixedAssoc do
    use Ecto.Schema

    @schema_prefix "other"

    schema "my_schema" do
      field :n, :integer
      belongs_to :parent, MyParentWithPrefix
    end
  end

  defmodule MySchemaEmbedsMany do
    use Ecto.Schema

    schema "my_schema" do
      field :x, :string
      embeds_many :embeds, MyEmbed, on_replace: :delete
    end
  end

  defmodule MySchemaEmbedsOne do
    use Ecto.Schema

    schema "my_schema" do
      field :x, :string
      embeds_one :embed, MyEmbed
    end
  end

  defmodule MySchemaNoPK do
    use Ecto.Schema

    @primary_key false
    schema "my_schema" do
      field :x, :string
      field :n, :integer
      has_one :child, MySchemaChild, references: :n, foreign_key: :n
    end
  end

  defmodule MySchemaWritable do
    use Ecto.Schema

    schema "my_schema" do
      field :never, :integer, writable: :never
      field :always, :integer, writable: :always
      field :insert, :integer, writable: :insert
    end
  end

  defmodule MySchemaOneField do
    use Ecto.Schema

    @primary_key false
    schema "my_schema" do
      field :n, :integer
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
             TestRepo.load(MySchema, x: "abc")

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
    assert_raise ArgumentError,
                 "cannot load `0` as type :string for field `x` in schema Ecto.RepoTest.MySchema",
                 fn ->
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

  describe "reload" do
    test "raises when input structs do not have valid primary keys" do
      message = "Ecto.Repo.reload/2 expects existent structs, found a `nil` primary key"

      assert_raise ArgumentError, message, fn ->
        TestRepo.reload(%MySchema{})
      end
    end

    test "raises when input is not a struct or a list of structs" do
      message = ~r"expected a struct or a list of structs,"

      assert_raise ArgumentError, message, fn ->
        TestRepo.reload(%{my_key: 1})
      end

      assert_raise ArgumentError, message, fn ->
        TestRepo.reload([%{my_key: 1}, %{my_key: 2}])
      end
    end

    test "raises when schema doesn't have a primary key" do
      message = ~r"to have exactly one primary key"

      assert_raise ArgumentError, message, fn ->
        TestRepo.reload(%MySchemaNoPK{})
      end
    end

    test "raises when receives multiple struct types" do
      message = ~r"expected an homogeneous list"

      assert_raise ArgumentError, message, fn ->
        TestRepo.reload([%MySchemaWithAssoc{id: 1}, %MySchema{id: 2}])
      end
    end

    test "supports prefix" do
      struct_with_prefix = put_meta(%MySchema{id: 2}, prefix: "another")
      TestRepo.reload(struct_with_prefix)
      assert_received {:all, %{prefix: "another"}}
    end

    test "supports non-string prefix" do
      struct_with_prefix = put_meta(%MySchema{id: 2}, prefix: %{key: :another})
      TestRepo.reload(struct_with_prefix)
      assert_received {:all, %{prefix: %{key: :another}}}
    end

    test "respects source" do
      struct_with_custom_source = put_meta(%MySchema{id: 2}, source: "custom_schema")
      TestRepo.reload(struct_with_custom_source)
      assert_received {:all, %{from: %{source: {"custom_schema", MySchema}}}}
    end

    test "returns empty list when given empty list" do
      assert TestRepo.reload([]) == []
    end

    test "reload! returns empty list when given empty list" do
      assert TestRepo.reload!([]) == []
    end
  end

  defmodule DefaultOptionRepo do
    use Ecto.Repo, otp_app: :ecto, adapter: Ecto.TestAdapter

    def default_options(:all), do: [prefix: "all_schema"]
    def default_options(:update_all), do: [prefix: "update_all_schema"]
    def default_options(_), do: [prefix: "fallback_schema"]
  end

  describe "default_options" do
    test "passes a default option for operation" do
      {:ok, _pid} = DefaultOptionRepo.start_link(url: "ecto://user:pass@local/hello")
      DefaultOptionRepo.all(MySchema)
      assert_received {:all, query}
      assert query.prefix == "all_schema"

      DefaultOptionRepo.all(MySchema, prefix: "overridden_schema")
      assert_received {:all, query}
      assert query.prefix == "overridden_schema"

      DefaultOptionRepo.update_all(MySchema, set: [x: "foo"])
      assert_received {:update_all, query}
      assert query.prefix == "update_all_schema"

      DefaultOptionRepo.delete_all(MySchema)
      assert_received {:delete_all, query}
      assert query.prefix == "fallback_schema"

      DefaultOptionRepo.preload(%MySchemaWithAssoc{parent_id: 1}, :parent)
      assert_received {:all, query}
      assert query.from.source == {"my_parent", Ecto.RepoTest.MyParent}
      assert query.prefix == "fallback_schema"
    end
  end

  describe "aggregate" do
    test "aggregates on the given field" do
      TestRepo.aggregate(MySchema, :min, :id)
      assert_received {:all, query}

      assert inspect(query) ==
               "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, select: min(m0.id)>"

      TestRepo.aggregate(MySchema, :max, :id)
      assert_received {:all, query}

      assert inspect(query) ==
               "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, select: max(m0.id)>"

      TestRepo.aggregate(MySchema, :sum, :id)
      assert_received {:all, query}

      assert inspect(query) ==
               "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, select: sum(m0.id)>"

      TestRepo.aggregate(MySchema, :avg, :id)
      assert_received {:all, query}

      assert inspect(query) ==
               "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, select: avg(m0.id)>"

      TestRepo.aggregate(MySchema, :count, :id)
      assert_received {:all, query}

      assert inspect(query) ==
               "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, select: count(m0.id)>"

      TestRepo.aggregate(MySchema, :count)
      assert_received {:all, query}
      assert inspect(query) == "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, select: count()>"
    end

    test "aggregates handle a prefix option" do
      TestRepo.aggregate(MySchema, :min, :id, prefix: "public")
      assert_received {:all, query}
      assert query.prefix == "public"
    end

    test "aggregate/3 respects parent query prefix" do
      query = from(m in MySchema, limit: 1) |> put_query_prefix("public")
      TestRepo.aggregate(query, :count)

      assert_received {:all, query}
      assert query.prefix == "public"
    end

    test "aggregate/4 respects parent query prefix" do
      query = from(m in MySchema, limit: 1) |> put_query_prefix("public")
      TestRepo.aggregate(query, :count, :id)

      assert_received {:all, query}
      assert query.prefix == "public"
    end

    test "removes any preload from query" do
      from(MySchemaWithAssoc, preload: :parent) |> TestRepo.aggregate(:count, :id)
      assert_received {:all, query}

      assert inspect(query) ==
               "#Ecto.Query<from m0 in Ecto.RepoTest.MySchemaWithAssoc, select: count(m0.id)>"
    end

    test "removes order by from query without distinct/limit/offset/combinations" do
      from(MySchema, order_by: :id) |> TestRepo.aggregate(:count, :id)
      assert_received {:all, query}

      assert inspect(query) ==
               "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, select: count(m0.id)>"
    end

    test "overrides any select" do
      from(MySchema, select: true) |> TestRepo.aggregate(:count, :id)
      assert_received {:all, query}

      assert inspect(query) ==
               "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, select: count(m0.id)>"
    end

    test "uses subqueries with distinct/limit/offset" do
      from(MySchema, limit: 5) |> TestRepo.aggregate(:count, :id)
      assert_received {:all, query}

      assert inspect(query) ==
               "#Ecto.Query<from m0 in subquery(from m0 in Ecto.RepoTest.MySchema,\n" <>
                 "  limit: 5,\n" <>
                 "  select: %{id: m0.id}), select: count(m0.id)>"
    end

    test "uses subqueries with combinations" do
      from(MySchema, union: ^from(MySchema)) |> TestRepo.aggregate(:count, :id)
      assert_received {:all, query}

      assert inspect(query) ==
               "#Ecto.Query<from m0 in subquery(from m0 in Ecto.RepoTest.MySchema,\n" <>
                 "  union: (from m0 in Ecto.RepoTest.MySchema,\n" <>
                 "  select: m0),\n" <>
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

      assert inspect(query) ==
               "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, limit: 1, select: 1>"

      from(MySchema, select: [:id], limit: 10) |> TestRepo.exists?()
      assert_received {:all, query}

      assert inspect(query) ==
               "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, limit: 1, select: 1>"
    end

    test "removes any preload from query" do
      from(MySchemaWithAssoc, preload: :parent) |> TestRepo.exists?()
      assert_received {:all, query}

      assert inspect(query) ==
               "#Ecto.Query<from m0 in Ecto.RepoTest.MySchemaWithAssoc, limit: 1, select: 1>"
    end

    test "removes distinct from query" do
      from(MySchema, select: [:id], distinct: true) |> TestRepo.exists?()
      assert_received {:all, query}

      assert inspect(query) ==
               "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, limit: 1, select: 1>"
    end

    test "keeps order by from query" do
      from(MySchema, order_by: :id) |> TestRepo.exists?()
      assert_received {:all, query}

      assert inspect(query) ==
               "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, order_by: [asc: m0.id], limit: 1, select: 1>"
    end

    test "overrides any select" do
      from(MySchema, select: true) |> TestRepo.exists?()
      assert_received {:all, query}

      assert inspect(query) ==
               "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, limit: 1, select: 1>"

      from(MySchema, union: ^from(MySchema, select: true)) |> TestRepo.exists?()
      assert_received {:all, query}

      assert inspect(query) ==
               "#Ecto.Query<from m0 in Ecto.RepoTest.MySchema, union: (from m0 in Ecto.RepoTest.MySchema,\n  select: 1), limit: 1, select: 1>"
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

  describe "returning" do
    test "on insert" do
      TestRepo.insert(%MySchemaWithAssoc{}, returning: [:id])
      assert_received {:insert, %{source: "my_schema", returning: [:id]}}
      TestRepo.insert(%MySchemaWithAssoc{}, returning: [:parent_id])
      assert_received {:insert, %{source: "my_schema", returning: [:id, :parent_id]}}
      TestRepo.insert(%MySchemaWithAssoc{}, returning: true)
      assert_received {:insert, %{source: "my_schema", returning: [:id, :parent_id, :n]}}
      TestRepo.insert(%MySchemaWithAssoc{}, returning: false)
      assert_received {:insert, %{source: "my_schema", returning: [:id]}}
    end

    test "on update" do
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

    test "on delete" do
      changeset = Ecto.Changeset.change(%MySchemaWithAssoc{id: 1}, %{n: 2})
      TestRepo.delete(changeset, returning: [:id])
      assert_received {:delete, %{source: "my_schema", returning: [:id]}}
      TestRepo.delete(changeset, returning: [:parent_id])
      assert_received {:delete, %{source: "my_schema", returning: [:parent_id]}}
      TestRepo.delete(changeset, returning: true)
      assert_received {:delete, %{source: "my_schema", returning: [:parent_id, :n, :id]}}
      TestRepo.delete(changeset, returning: false)
      assert_received {:delete, %{source: "my_schema", returning: []}}
    end
  end

  describe "insert_all" do
    test "takes queries as values in rows" do
      import Ecto.Query

      value = "foo"
      query = from(s in MySchema, select: s.x, where: s.y == ^value)

      TestRepo.insert_all(MySchema, [
        [y: "y1", x: "x1"],
        [x: query, z: "z2"],
        [z: "z3", x: query],
        [y: query, z: query]
      ])

      assert_received {:insert_all, %{source: "my_schema", header: header}, planned_rows}

      assert [
               [x: "x1", yyy: "y1"],
               [x: {%Ecto.Query{}, [^value]}, z: "z2"],
               [x: {%Ecto.Query{}, [^value]}, z: "z3"],
               [yyy: {%Ecto.Query{}, [^value]}, z: {%Ecto.Query{}, [^value]}]
             ] = planned_rows

      {queries_with_index, _} =
        for row <- planned_rows, field <- header, reduce: {[], 0} do
          {queries, ix} ->
            case row[field] do
              {%Ecto.Query{} = query, _} -> {[{ix, query} | queries], ix + 1}
              nil -> {queries, ix}
              _ -> {queries, ix + 1}
            end
        end

      assert length(queries_with_index) == 4

      Enum.each(queries_with_index, fn {ix, query} ->
        assert [%{expr: {:==, _, [_, {:^, [], [^ix]}]}}] = query.wheres
      end)
    end

    test "takes query selecting on map" do
      import Ecto.Query

      threshold = "ten"

      query =
        from s in MySchema,
          where: s.x > ^threshold,
          select: %{
            x: s.x,
            y: fragment("concat(?, ?, ?)", ^"one", ^"two", s.z)
          }

      TestRepo.insert_all(MySchema, query)

      assert_received {:insert_all, %{source: "my_schema"}, {%Ecto.Query{}, params}}

      assert ["one", "two", "ten"] = params
    end

    test "takes query selecting on map with literals" do
      threshold = "ten"

      query =
        from s in MySchema,
          where: s.x > ^threshold,
          select: %{
            x: s.x,
            y: "bar",
            z: nil
          }

      TestRepo.insert_all(MySchema, query)

      assert_received {:insert_all, %{source: "my_schema"}, {%Ecto.Query{} = query, params}}
      assert [{{:., _, [{:&, [], [0]}, :x]}, _, []}, "bar", nil] = query.select.fields
      assert ["ten"] = params
    end

    test "takes query selecting on struct/2" do
      query =
        from s in MySchema,
          select: struct(s, [:x, :y])

      TestRepo.insert_all(MySchema, query)

      assert_received {:insert_all, %{source: "my_schema"}, {%Ecto.Query{}, _params}}
    end

    test "takes query selecting on map/2" do
      query =
        from s in MySchema,
          select: map(s, [:x, :y])

      TestRepo.insert_all(MySchema, query)

      assert_received {:insert_all, %{source: "my_schema"}, {%Ecto.Query{}, _params}}
    end

    test "takes query selecting on source" do
      query = from s in MySchema, select: s
      TestRepo.insert_all(MySchema, query)

      assert_received {:insert_all, %{source: "my_schema", header: header},
                       {%Ecto.Query{}, _params}}

      assert header == [:id, :x, :yyy, :z, :array, :map]
    end

    test "takes query selecting on source with join" do
      query = from p in MyParent, join: a in MySchemaWithAssoc, on: true, select: a
      TestRepo.insert_all(MySchemaWithAssoc, query)

      assert_received {:insert_all, %{source: "my_schema", header: header},
                       {%Ecto.Query{}, _params}}

      assert header == [:id, :n, :parent_id]
    end

    test "takes query selecting on source with literal update" do
      query = from s in MySchema, select: %{s | x: "x"}
      TestRepo.insert_all(MySchema, query)

      assert_received {:insert_all, %{source: "my_schema", header: header},
                       {%Ecto.Query{} = query, _params}}

      unchanged_fields = [:id, :yyy, :z, :array, :map]
      updated_fields = [:x]
      updated_values = ["x"]

      assert header == unchanged_fields ++ updated_fields
      assert query.select.fields == select_fields(unchanged_fields, 0) ++ updated_values
    end

    test "takes query selecting on source with dynamic update" do
      query = from s in MySchema, select: %{s | x: ^"x"}
      TestRepo.insert_all(MySchema, query)

      assert_received {:insert_all, %{source: "my_schema", header: header},
                       {%Ecto.Query{} = query, _params}}

      unchanged_fields = [:id, :yyy, :z, :array, :map]
      updated_fields = [:x]
      updated_values = [%Ecto.Query.Tagged{tag: :string, type: :string, value: {:^, [], [0]}}]

      assert header == unchanged_fields ++ updated_fields
      assert query.select.fields == select_fields(unchanged_fields, 0) ++ updated_values
    end

    test "takes query selecting on source with join column update" do
      query =
        from p in MyParent, join: a in MySchemaWithAssoc, on: true, select: %{p | id: a.parent_id}

      TestRepo.insert_all(MySchemaWithAssoc, query)

      assert_received {:insert_all, %{source: "my_schema", header: header},
                       {%Ecto.Query{} = query, _params}}

      unchanged_fields = [:n]
      updated_fields = [:id]
      updated_values = [{{:., [type: :id], [{:&, [], [1]}, :parent_id]}, [], []}]

      assert header == unchanged_fields ++ updated_fields
      assert query.select.fields == select_fields(unchanged_fields, 0) ++ updated_values
    end

    test "takes query selecting on source with update from same source" do
      # no join
      query = from s in MySchema, select: %{s | x: s.y, y: s.x}
      TestRepo.insert_all(MySchema, query)

      assert_received {:insert_all, %{source: "my_schema", header: header},
                       {%Ecto.Query{} = query, _params}}

      unchanged_fields = [:id, :z, :array, :map]
      updated_fields = [:x, :yyy]

      updated_values = [
        {{:., [type: :binary], [{:&, [], [0]}, :yyy]}, [], []},
        {{:., [type: :string], [{:&, [], [0]}, :x]}, [], []}
      ]

      assert header == unchanged_fields ++ updated_fields
      assert query.select.fields == select_fields(unchanged_fields, 0) ++ updated_values

      # join
      query =
        from s in MySchema,
          join: a in MySchemaWithAssoc,
          on: true,
          select: %{a | n: a.parent_id, parent_id: a.n}

      TestRepo.insert_all(MySchemaWithAssoc, query)

      assert_received {:insert_all, %{source: "my_schema", header: header},
                       {%Ecto.Query{} = query, _params}}

      unchanged_fields = [:id]
      updated_fields = [:n, :parent_id]

      updated_values = [
        {{:., [type: :id], [{:&, [], [1]}, :parent_id]}, [], []},
        {{:., [type: :integer], [{:&, [], [1]}, :n]}, [], []}
      ]

      assert header == unchanged_fields ++ updated_fields
      assert query.select.fields == select_fields(unchanged_fields, 1) ++ updated_values
    end

    test "takes query selecting on map/2 with update" do
      query = from s in MySchema, select: %{map(s, [:id, :x, :z]) | x: "x"}
      TestRepo.insert_all(MySchema, query)

      assert_received {:insert_all, %{source: "my_schema", header: header},
                       {%Ecto.Query{} = query, _params}}

      unchanged_fields = [:id, :z]
      updated_fields = [:x]
      updated_values = ["x"]

      assert header == unchanged_fields ++ updated_fields
      assert query.select.fields == select_fields(unchanged_fields, 0) ++ updated_values
    end

    test "raises with query selecting read only fields" do
      msg = ~r"cannot select unwritable field"

      assert_raise ArgumentError, msg, fn ->
        TestRepo.insert_all(MySchemaWritable, from(w in MySchemaWritable, select: w))
      end
    end

    test "raises when a bad query is given as source" do
      assert_raise ArgumentError, fn ->
        TestRepo.insert_all(MySchema, from(s in MySchema))
      end

      assert_raise ArgumentError, fn ->
        source =
          from s in MySchema,
            select: s.x

        TestRepo.insert_all(MySchema, source)
      end

      assert_raise Ecto.QueryError, fn ->
        source = from s in MySchema, select: map(s, [])
        TestRepo.insert_all(MySchema, source)
      end
    end

    test "raises when on associations" do
      assert_raise ArgumentError, fn ->
        TestRepo.insert_all(MySchema, [%{another: nil}])
      end
    end

    test "with an embeds_one field" do
      TestRepo.insert_all(MySchemaEmbedsOne, [%{embed: %MyEmbed{x: "x"}}])
      assert_received {:insert_all, %{source: "my_schema"}, [row]}
      assert [embed: %{id: nil, x: "x"}] = row
    end

    test "with an embeds_many field" do
      TestRepo.insert_all(MySchemaEmbedsMany, [%{embeds: [%MyEmbed{x: "x"}]}])
      assert_received {:insert_all, %{source: "my_schema"}, [row]}
      assert [embeds: [%{id: nil, x: "x"}]] = row
    end

    test "raises when an embedded struct is needed" do
      assert_raise ArgumentError, ~r"expected a struct #{inspect(MyEmbed)} value", fn ->
        TestRepo.insert_all(MySchemaEmbedsOne, [%{embed: %{x: "x"}}])
      end

      assert_raise ArgumentError, ~r"expected a list of #{inspect(MyEmbed)} struct values", fn ->
        TestRepo.insert_all(MySchemaEmbedsMany, [%{embeds: [%{x: "x"}]}])
      end
    end
  end

  defmodule MySchemaWithBinaryId do
    use Ecto.Schema

    schema "my_schema_with_binary_id" do
      field :bid, :binary_id
      field :str, :string
    end
  end

  describe "placeholders" do
    @describetag :placeholders

    test "Repo.insert_all supports placeholder keys with schema" do
      TestRepo.insert_all(MySchema, [%{x: {:placeholder, :foo}}], placeholders: %{foo: "bar"})
      assert_receive {:insert_all, meta, query}
      assert meta.placeholders == ["bar"]
      assert query == [[x: {:placeholder, 1}]]
    end

    test "Repo.insert_all supports placeholder keys without schema" do
      TestRepo.insert_all("my_schema", [%{x: {:placeholder, :foo}}], placeholders: %{foo: "bar"})
      assert_receive {:insert_all, meta, query}
      assert meta.placeholders == ["bar"]
      assert query == [[x: {:placeholder, 1}]]
    end

    test "Repo.insert_all raises when placeholder key is not found" do
      assert_raise KeyError, fn ->
        TestRepo.insert_all(MySchema, [%{x: {:placeholder, :bad_key}}], placeholders: %{foo: 100})
      end
    end

    test "Repo.insert_all raises when placeholder key is used for different types" do
      placeholders = %{uuid_key: Ecto.UUID.generate()}
      ph_key = {:placeholder, :uuid_key}
      entries = [%{bid: ph_key, string: ph_key}]

      assert_raise ArgumentError, fn ->
        TestRepo.insert_all(MySchemaWithBinaryId, entries, placeholders: placeholders)
      end
    end

    test "Repo.insert_all raises when placeholder key is used with invalid types" do
      placeholders = %{string_key: "foo"}
      entries = [%{n: {:placeholder, :string_key}}]

      assert_raise Ecto.ChangeError, fn ->
        TestRepo.insert_all(MyParent, entries, placeholders: placeholders)
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
        TestRepo.update_all(from(e in MySchema, order_by: e.x), set: [x: "321"])
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
        TestRepo.delete_all(from(e in MySchema, order_by: e.x))
      end
    end
  end

  describe "schema operations" do
    test "needs schema with primary key field" do
      schema = %MySchemaNoPK{x: "abc"}

      assert_raise Ecto.NoPrimaryKeyFieldError, fn ->
        TestRepo.update!(schema |> Ecto.Changeset.change(), force: true)
      end

      assert_raise Ecto.NoPrimaryKeyFieldError, fn ->
        TestRepo.delete!(schema)
      end
    end

    test "works with primary key value" do
      schema = %MySchema{id: 1, x: "abc"}
      TestRepo.get(MySchema, 123)
      TestRepo.get_by(MySchema, x: "abc")
      TestRepo.update!(schema |> Ecto.Changeset.change(), force: true)
      TestRepo.delete!(schema)
    end

    test "fails without primary key value" do
      schema = %MySchema{x: "abc"}

      assert_raise Ecto.NoPrimaryKeyValueError, fn ->
        TestRepo.update!(schema |> Ecto.Changeset.change(), force: true)
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
      TestRepo.update!(schema |> Ecto.Changeset.change(), force: true)
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
      valid = put_in(valid.changes[:unknown], "foo")

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

      try do
        TestRepo.update(stale)
      rescue
        e in Ecto.StaleEntryError ->
          assert %Ecto.Changeset{} = e.changeset
      end
    end

    test "insert, update, and delete adds error to stale error field" do
      my_schema = %MySchema{id: 1}
      my_schema = put_in(my_schema.__meta__.context, {:error, :stale})
      stale = Ecto.Changeset.cast(my_schema, %{x: "foo"}, [:x])

      assert {:error, changeset} = TestRepo.insert(stale, stale_error_field: :id)
      assert changeset.errors == [id: {"is stale", [stale: true]}]

      assert {:error, changeset} = TestRepo.update(stale, stale_error_field: :id)
      assert changeset.errors == [id: {"is stale", [stale: true]}]

      assert {:error, changeset} = TestRepo.delete(stale, stale_error_field: :id)
      assert changeset.errors == [id: {"is stale", [stale: true]}]

      assert_raise Ecto.StaleEntryError, fn -> TestRepo.insert(stale, stale_error_field: "id") end
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

    test "insert, update, and delete allows stale with :allow_stale option" do
      my_schema = %MySchema{id: 1}
      my_schema = put_in(my_schema.__meta__.context, {:error, :stale})

      stale = Ecto.Changeset.cast(my_schema, %{x: "foo"}, [:x])

      assert {:ok, _} = TestRepo.insert(stale, allow_stale: true)
      assert {:ok, _} = TestRepo.update(stale, allow_stale: true)
      assert {:ok, _} = TestRepo.delete(stale, allow_stale: true)
    end

    test "insert, update allows stale children with :allow_stale option" do
      child_schema =
        %MySchemaChild{a: "one"}

      stale =
        put_in(child_schema.__meta__.context, {:error, :stale})
        |> Ecto.Changeset.change()

      changeset =
        %MySchema{id: 1}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:children, [stale])

      assert {:ok, _} = TestRepo.insert(changeset, allow_stale: true)
      assert {:ok, _} = TestRepo.update(changeset, allow_stale: true)
    end

    test "insert and delete sets schema prefix with struct" do
      valid = %MySchema{id: 1}

      assert {:ok, schema} = TestRepo.insert(valid, prefix: "public")
      assert schema.__meta__.prefix == "public"

      assert {:ok, schema} = TestRepo.delete(valid, prefix: "public")
      assert schema.__meta__.prefix == "public"

      assert {:ok, schema} = TestRepo.insert(valid, prefix: %{key: :public})
      assert schema.__meta__.prefix == %{key: :public}

      assert {:ok, schema} = TestRepo.delete(valid, prefix: %{key: :public})
      assert schema.__meta__.prefix == %{key: :public}
    end

    test "insert and delete prefix overrides schema_prefix with struct" do
      valid = %MySchemaWithPrefix{id: 1}

      assert {:ok, schema} = TestRepo.insert(valid, prefix: "public")
      assert schema.__meta__.prefix == "public"

      assert {:ok, schema} = TestRepo.delete(valid, prefix: "public")
      assert schema.__meta__.prefix == "public"
    end

    test "insert and delete prefix overrides schema_prefix with struct when prefix is not a string" do
      valid = %MySchemaWithNonStringPrefix{id: 1}

      assert {:ok, schema} = TestRepo.insert(valid, prefix: %{key: :public})
      assert schema.__meta__.prefix == %{key: :public}

      assert {:ok, schema} = TestRepo.delete(valid, prefix: %{key: :public})
      assert schema.__meta__.prefix == %{key: :public}
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
        |> Map.put(:repo_opts, prefix: "public")

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
        |> Map.put(:repo_opts, prefix: "public")

      assert {:ok, schema} = TestRepo.insert(valid, prefix: "private")
      assert schema.__meta__.prefix == "private"

      assert {:ok, schema} = TestRepo.update(valid, prefix: "private")
      assert schema.__meta__.prefix == "private"

      assert {:ok, schema} = TestRepo.delete(valid, prefix: "private")
      assert schema.__meta__.prefix == "private"
    end

    test "insert, update and insert_or_update parent schema_prefix does not override `nil` children schema_prefix" do
      assert {:ok, schema} = TestRepo.insert(%MyParentWithPrefix{id: 1})
      assert schema.__meta__.prefix == "private"

      valid =
        %MySchemaWithPrefixedAssoc{id: 1}
        |> TestRepo.preload(:parent)
        |> Ecto.Changeset.cast(%{parent: %{id: 1}}, [])
        |> Ecto.Changeset.cast_assoc(:parent)

      assert {:ok, schema} = TestRepo.insert(valid)
      assert schema.__meta__.prefix == nil
      assert schema.parent.__meta__.prefix == "private"

      assert {:ok, schema} = TestRepo.insert_or_update(valid)
      assert schema.__meta__.prefix == nil
      assert schema.parent.__meta__.prefix == "private"

      assert {:ok, schema} = TestRepo.update(valid)
      assert schema.__meta__.prefix == nil
      assert schema.parent.__meta__.prefix == "private"
    end

    test "insert, update and insert_or_update `nil` parent schema_prefix is overridden by children schema_prefix" do
      assert {:ok, schema} = TestRepo.insert(%MyParent{id: 1})
      assert schema.__meta__.prefix == nil

      valid =
        %MyPrefixedSchemaWithAssoc{id: 1}
        |> TestRepo.preload(:parent)
        |> Ecto.Changeset.cast(%{parent: %{id: 1}}, [])
        |> Ecto.Changeset.cast_assoc(:parent)

      assert {:ok, schema} = TestRepo.insert(valid)
      assert schema.__meta__.prefix == "other"
      assert schema.parent.__meta__.prefix == "other"

      assert {:ok, schema} = TestRepo.insert_or_update(valid)
      assert schema.__meta__.prefix == "other"
      assert schema.parent.__meta__.prefix == "other"

      assert {:ok, schema} = TestRepo.update(valid)
      assert schema.__meta__.prefix == "other"
      assert schema.parent.__meta__.prefix == "other"
    end

    test "insert, update and insert_or_update parent schema_prefix does not override children schema_prefix" do
      assert {:ok, schema} = TestRepo.insert(%MyParentWithPrefix{id: 1})
      assert schema.__meta__.prefix == "private"

      valid =
        %MyPrefixedSchemaWithPrefixedAssoc{id: 1}
        |> TestRepo.preload(:parent)
        |> Ecto.Changeset.cast(%{parent: %{id: 1}}, [])
        |> Ecto.Changeset.cast_assoc(:parent)

      assert {:ok, schema} = TestRepo.insert(valid)
      assert schema.__meta__.prefix == "other"
      assert schema.parent.__meta__.prefix == "private"

      assert {:ok, schema} = TestRepo.insert_or_update(valid)
      assert schema.__meta__.prefix == "other"
      assert schema.parent.__meta__.prefix == "private"

      assert {:ok, schema} = TestRepo.update(valid)
      assert schema.__meta__.prefix == "other"
      assert schema.parent.__meta__.prefix == "private"
    end

    test "insert, update and insert_or_update prefix overrides schema_prefix in associations" do
      valid =
        %MySchemaWithPrefixedAssoc{id: 1}
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
        %MySchemaWithPrefixedAssoc{id: 1}
        |> TestRepo.preload(:parent)
        |> Ecto.Changeset.cast(%{parent: %{n: 1}}, [])
        |> Ecto.Changeset.cast_assoc(:parent)

      valid = put_in(valid.changes.parent.repo_opts, prefix: "public")

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

      assert_raise ArgumentError,
                   ~r"a valid changeset with action :ignore was given to Ecto.TestRepo.insert/2",
                   fn ->
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
                   ~r"could not perform insert because changeset is invalid",
                   fn ->
                     TestRepo.insert!(invalid)
                   end

      assert_raise Ecto.InvalidChangesetError,
                   ~r"could not perform update because changeset is invalid",
                   fn ->
                     TestRepo.update!(invalid)
                   end

      assert_raise Ecto.InvalidChangesetError,
                   ~r"could not perform insert because changeset is invalid",
                   fn ->
                     TestRepo.insert_or_update!(invalid)
                   end

      assert_raise Ecto.InvalidChangesetError,
                   ~r"could not perform delete because changeset is invalid",
                   fn ->
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

      assert_raise ArgumentError,
                   "a changeset with action :other was given to Ecto.TestRepo.insert/2",
                   fn ->
                     TestRepo.insert!(invalid)
                   end

      assert_raise ArgumentError,
                   "a changeset with action :other was given to Ecto.TestRepo.update/2",
                   fn ->
                     TestRepo.update!(invalid)
                   end

      assert_raise ArgumentError,
                   "a changeset with action :other was given to Ecto.TestRepo.insert/2",
                   fn ->
                     TestRepo.insert_or_update!(invalid)
                   end

      assert_raise ArgumentError,
                   "a changeset with action :other was given to Ecto.TestRepo.delete/2",
                   fn ->
                     TestRepo.delete!(invalid)
                   end
    end

    test "insert_or_update uses the correct action" do
      built = Ecto.Changeset.cast(%MySchema{y: "built"}, %{}, [])

      loaded =
        %MySchema{y: "loaded"}
        |> TestRepo.insert!()
        |> Ecto.Changeset.cast(%{y: "updated"}, [:y])

      assert_received {:insert, _}

      TestRepo.insert_or_update(built)
      assert_received {:insert, _}

      TestRepo.insert_or_update(loaded)
      assert_received {:update, _}
    end

    test "insert_or_update fails on invalid states" do
      deleted =
        %MySchema{y: "deleted"}
        |> TestRepo.insert!()
        |> TestRepo.delete!()
        |> Ecto.Changeset.cast(%{y: "updated"}, [:y])

      assert_raise ArgumentError, ~r/the changeset has an invalid state/, fn ->
        TestRepo.insert_or_update(deleted)
      end
    end

    test "insert_or_update fails when being passed a struct" do
      assert_raise ArgumentError, ~r/giving a struct to .* is not supported/, fn ->
        TestRepo.insert_or_update(%MySchema{})
      end
    end

    test "insert surfaces embed fields" do
      # embeds_one
      inserted =
        %MySchemaEmbedsOne{embed: %MyEmbed{x: "old_x", y: "old_y"}}
        |> Ecto.Changeset.cast(%{embed: %{x: "new_x"}}, [])
        |> Ecto.Changeset.cast_embed(:embed)
        |> TestRepo.insert!()

      assert %{x: "new_x", y: "old_y"} = inserted.embed

      # embeds_many
      data_embed1 = %MyEmbed{id: 1, x: "old_x_1", y: "old_y_1"}
      data_embed2 = %MyEmbed{id: 2, x: "old_x_2"}

      inserted =
        %MySchemaEmbedsMany{embeds: [data_embed1, data_embed2]}
        |> Ecto.Changeset.cast(%{embeds: [%{id: 1, x: "new_x_1"}, %{}]}, [])
        |> Ecto.Changeset.cast_embed(:embeds)
        |> TestRepo.insert!()

      assert [%{id: 1, x: "new_x_1", y: "old_y_1"}, %{id: new_id, x: nil}] = inserted.embeds
      assert new_id != data_embed2.id
    end
  end

  test "get, get_by, one, all and all_by sets schema prefix" do
    assert schema = TestRepo.get(MySchema, 123, prefix: "public")
    assert schema.__meta__.prefix == "public"

    assert schema = TestRepo.get_by(MySchema, [id: 123], prefix: "public")
    assert schema.__meta__.prefix == "public"

    assert schema = TestRepo.one(MySchema, prefix: "public")
    assert schema.__meta__.prefix == "public"

    assert [schema] = TestRepo.all(MySchema, prefix: "public")
    assert schema.__meta__.prefix == "public"

    assert [schema] = TestRepo.all_by(MySchema, [id: 123], prefix: "public")
    assert schema.__meta__.prefix == "public"

    assert schema = TestRepo.get(MySchema, 123, prefix: %{key: :public})
    assert schema.__meta__.prefix == %{key: :public}

    assert schema = TestRepo.get_by(MySchema, [id: 123], prefix: %{key: :public})
    assert schema.__meta__.prefix == %{key: :public}

    assert schema = TestRepo.one(MySchema, prefix: %{key: :public})
    assert schema.__meta__.prefix == %{key: :public}

    assert [schema] = TestRepo.all(MySchema, prefix: %{key: :public})
    assert schema.__meta__.prefix == %{key: :public}
  end

  test "get, get_by, one, all, and all_by ignores prefix if schema_prefix set" do
    assert schema = TestRepo.get(MySchemaWithPrefix, 123, prefix: "public")
    assert schema.__meta__.prefix == "private"

    assert schema = TestRepo.get_by(MySchemaWithPrefix, [id: 123], prefix: "public")
    assert schema.__meta__.prefix == "private"

    assert schema = TestRepo.one(MySchemaWithPrefix, prefix: "public")
    assert schema.__meta__.prefix == "private"

    assert [schema] = TestRepo.all(MySchemaWithPrefix, prefix: "public")
    assert schema.__meta__.prefix == "private"

    assert schema = TestRepo.get(MySchemaWithNonStringPrefix, 123, prefix: %{key: :public})
    assert schema.__meta__.prefix == %{key: :private}

    assert schema =
             TestRepo.get_by(MySchemaWithNonStringPrefix, [id: 123], prefix: %{key: :public})

    assert schema.__meta__.prefix == %{key: :private}

    assert schema = TestRepo.one(MySchemaWithNonStringPrefix, prefix: %{key: :public})
    assert schema.__meta__.prefix == %{key: :private}

    assert [schema] = TestRepo.all(MySchemaWithNonStringPrefix, prefix: %{key: :public})
    assert schema.__meta__.prefix == %{key: :private}

    assert [schema] =
             TestRepo.all_by(MySchemaWithNonStringPrefix, [id: 123], prefix: %{key: :public})

    assert schema.__meta__.prefix == %{key: :private}
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
      refute_received {:transaction, _, _}
    end

    test "insert runs prepare callbacks in transaction" do
      changeset = prepare_changeset()
      TestRepo.insert!(changeset)
      assert_received {:transaction, _, _}
      assert Process.get(:ecto_repo) == TestRepo
      assert Process.get(:ecto_counter) == 2
    end

    test "insert with prepare_changes that returns invalid changeset" do
      changeset =
        prepare_changeset()
        |> Ecto.Changeset.prepare_changes(fn changeset ->
          Ecto.Changeset.add_error(changeset, :x, "stop")
        end)

      assert {:error, %Ecto.Changeset{} = changeset} = TestRepo.insert(changeset)
      assert {:x, {"stop", []}} in changeset.errors
    end

    test "insert with prepare_changes that returns invalid children changeset" do
      changeset =
        %MySchema{id: 1}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.prepare_changes(fn changeset ->
          child_changeset =
            %MySchemaChild{a: "one"}
            |> Ecto.Changeset.change()
            |> Ecto.Changeset.add_error(:a, "stop")

          Ecto.Changeset.put_assoc(changeset, :children, [child_changeset])
        end)

      assert {:error, %Ecto.Changeset{} = changeset} = TestRepo.insert(changeset)
      assert {:a, {"stop", []}} in hd(changeset.changes.children).errors
    end

    test "insert with prepare_changes that returns invalid parent changeset" do
      changeset =
        %MySchemaWithAssoc{id: 1}
        |> Ecto.Changeset.change(n: 2)
        |> Ecto.Changeset.prepare_changes(fn changeset ->
          parent_changeset =
            %MyParent{}
            |> Ecto.Changeset.change()
            |> Ecto.Changeset.prepare_changes(&Ecto.Changeset.add_error(&1, :n, "stop"))

          Ecto.Changeset.put_assoc(changeset, :parent, parent_changeset)
        end)

      assert {:error, %Ecto.Changeset{} = changeset} = TestRepo.insert(changeset)
      assert {:n, {"stop", []}} in changeset.changes.parent.errors
    end

    test "update runs prepare callbacks in transaction" do
      changeset = prepare_changeset()
      TestRepo.update!(changeset)
      assert_received {:transaction, _, _}
      assert Process.get(:ecto_repo) == TestRepo
      assert Process.get(:ecto_counter) == 2
    end

    test "update with prepare_changes that returns invalid changeset" do
      changeset =
        prepare_changeset()
        |> Ecto.Changeset.prepare_changes(fn changeset ->
          Ecto.Changeset.add_error(changeset, :x, "stop")
        end)

      assert {:error, %Ecto.Changeset{} = changeset} = TestRepo.update(changeset)
      assert {:x, {"stop", []}} in changeset.errors
    end

    test "update with prepare_changes that returns invalid children changeset" do
      changeset =
        %MySchema{id: 1}
        |> Ecto.Changeset.change(x: 2)
        |> Ecto.Changeset.prepare_changes(fn changeset ->
          child_changeset =
            %MySchemaChild{a: "one"}
            |> Ecto.Changeset.change()
            |> Ecto.Changeset.add_error(:a, "stop")

          Ecto.Changeset.put_assoc(changeset, :children, [child_changeset])
        end)

      assert {:error, %Ecto.Changeset{} = changeset} = TestRepo.update(changeset)
      assert {:a, {"stop", []}} in hd(changeset.changes.children).errors
    end

    test "update with prepare_changes that returns invalid parent changeset" do
      changeset =
        %MySchemaWithAssoc{id: 1}
        |> Ecto.Changeset.change(n: 2)
        |> Ecto.Changeset.prepare_changes(fn changeset ->
          parent_changeset =
            %MyParent{}
            |> Ecto.Changeset.change()
            |> Ecto.Changeset.add_error(:n, "stop")

          Ecto.Changeset.put_assoc(changeset, :parent, parent_changeset)
        end)

      assert {:error, %Ecto.Changeset{} = changeset} = TestRepo.update(changeset)
      assert {:n, {"stop", []}} in changeset.changes.parent.errors
    end

    test "delete runs prepare callbacks in transaction" do
      changeset = prepare_changeset()
      TestRepo.delete!(changeset)
      assert_received {:transaction, _, _}
      assert Process.get(:ecto_repo) == TestRepo
      assert Process.get(:ecto_counter) == 2
    end

    test "delete with prepare_changes that returns invalid changeset" do
      changeset =
        prepare_changeset()
        |> Ecto.Changeset.prepare_changes(fn changeset ->
          Ecto.Changeset.add_error(changeset, :x, "stop")
        end)

      assert {:error, %Ecto.Changeset{} = changeset} = TestRepo.delete(changeset)
      assert {:x, {"stop", []}} in changeset.errors
    end

    test "delete with prepare_changes that returns invalid children changeset" do
      changeset =
        %MySchema{id: 1}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.prepare_changes(fn changeset ->
          child_changeset =
            %MySchemaChild{a: "one"}
            |> Ecto.Changeset.change()
            |> Ecto.Changeset.add_error(:a, "stop")

          Ecto.Changeset.put_assoc(changeset, :children, [child_changeset])
        end)

      assert {:error, %Ecto.Changeset{} = changeset} = TestRepo.delete(changeset)
      assert {:a, {"stop", []}} in hd(changeset.changes.children).errors
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
        %MySchemaEmbedsMany{id: 1}
        |> Ecto.Changeset.cast(%{x: "one"}, [:x])
        |> Ecto.Changeset.put_embed(:embeds, [embed_changeset])

      %MySchemaEmbedsMany{embeds: [embed]} = TestRepo.insert!(changeset)
      assert embed.x == "ONE"
      assert_received {:transaction, _, _}
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

    test "are mapped to repo constraint violation using regex match" do
      my_schema = %MySchema{id: 1}

      changeset =
        put_in(
          my_schema.__meta__.context,
          {:invalid, [unique: "foo_table_part_90_custom_foo_index1234"]}
        )
        |> Ecto.Changeset.change(x: "foo")
        |> Ecto.Changeset.unique_constraint(:foo, name: ~r/foo_table_part_.+_custom_foo_index\d+/)

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

    test "may fail to map to repo constraint violation on name regex" do
      my_schema = %MySchema{id: 1}

      changeset =
        put_in(my_schema.__meta__.context, {:invalid, [unique: "foo_table_custom_foo_index"]})
        |> Ecto.Changeset.change(x: "foo")
        |> Ecto.Changeset.unique_constraint(:foo, name: ~r/will_not_match/)

      assert_raise Ecto.ConstraintError, fn ->
        TestRepo.insert(changeset)
      end
    end

    test "may fail to map to repo constraint violation on index type" do
      my_schema = %MySchema{id: 1}

      changeset =
        put_in(
          my_schema.__meta__.context,
          {:invalid, [invalid_constraint_type: "my_schema_foo_index"]}
        )
        |> Ecto.Changeset.change(x: "foo")
        |> Ecto.Changeset.unique_constraint(:foo)

      assert_raise Ecto.ConstraintError, fn ->
        TestRepo.insert(changeset)
      end
    end
  end

  describe "on conflict" do
    test "passes all fields on replace_all" do
      fields = [:map, :array, :z, :yyy, :x, :id]
      TestRepo.insert(%MySchema{id: 1}, on_conflict: :replace_all)
      assert_received {:insert, %{source: "my_schema", on_conflict: {^fields, [], []}}}
    end

    test "passes all fields+embeds on replace_all" do
      fields = [:embeds, :x, :id]
      TestRepo.insert(%MySchemaEmbedsMany{id: 1}, on_conflict: :replace_all)
      assert_received {:insert, %{source: "my_schema", on_conflict: {^fields, [], []}}}
    end

    test "replaces specified fields on replace" do
      fields = [:x, :yyy]
      TestRepo.insert(%MySchema{id: 1}, on_conflict: {:replace, [:x, :y]})
      assert_received {:insert, %{source: "my_schema", on_conflict: {^fields, [], []}}}
    end

    test "replaces specified fields on replace without a schema" do
      fields = [:x, :yyy]
      rows = [[id: 1, x: "x", yyy: "yyy"]]
      TestRepo.insert_all("my_schema", rows, on_conflict: {:replace, [:x, :yyy]})
      assert_received {:insert_all, %{source: "my_schema", on_conflict: {^fields, [], []}}, ^rows}
    end

    test "raises on non-existent fields on replace" do
      msg = "cannot replace non-updatable field `:unknown` in :on_conflict option"

      assert_raise ArgumentError, msg, fn ->
        TestRepo.insert(
          %MySchema{id: 1},
          on_conflict: {:replace, [:unknown]}
        )
      end
    end

    test "passes all fields except given fields" do
      fields = [:map, :z, :yyy, :x]
      TestRepo.insert(%MySchema{id: 1}, on_conflict: {:replace_all_except, [:id, :array]})
      assert_received {:insert, %{source: "my_schema", on_conflict: {^fields, [], []}}}
    end

    test "includes conflict target in the field list given to :replace_all_except" do
      fields = [:map, :z, :yyy, :x]

      TestRepo.insert(%MySchema{id: 1},
        on_conflict: {:replace_all_except, [:array]},
        conflict_target: [:id]
      )

      assert_received {:insert, %{source: "my_schema", on_conflict: {^fields, [], [:id]}}}
    end

    test "raises on empty-list of fields to update when :replace_all_except is given" do
      msg = "empty list of fields to update, use the `:replace` option instead"

      assert_raise ArgumentError, msg, fn ->
        TestRepo.insert(%MySchema{id: 1},
          on_conflict: {:replace_all_except, [:array, :map, :z, :y, :x]},
          conflict_target: [:id]
        )
      end
    end

    test "excludes conflict target from :replace_all" do
      fields = [:map, :array, :z, :yyy, :x]
      TestRepo.insert(%MySchema{id: 1}, on_conflict: :replace_all, conflict_target: [:id])
      assert_received {:insert, %{source: "my_schema", on_conflict: {^fields, [], [:id]}}}
    end

    test "raises on empty-list of fields to update when :replace_all is given" do
      msg = "empty list of fields to update, use the `:replace` option instead"

      assert_raise ArgumentError, msg, fn ->
        TestRepo.insert(%MySchemaOneField{n: 1},
          on_conflict: :replace_all,
          conflict_target: [:n]
        )
      end
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

    test "raises on empty list of replace fields" do
      msg = ":on_conflict option with `{:replace, fields}` requires a non-empty list of fields"

      assert_raise ArgumentError, msg, fn ->
        TestRepo.insert(%MySchema{id: 1}, on_conflict: {:replace, []})
      end
    end

    test "raises on unknown on_conflict value" do
      assert_raise ArgumentError, "unknown value for :on_conflict, got: :who_knows", fn ->
        TestRepo.insert(%MySchema{id: 1}, on_conflict: :who_knows)
      end
    end

    test "raises on non-empty conflict_target with on_conflict raise" do
      assert_raise ArgumentError,
                   ":conflict_target option is forbidden when :on_conflict is :raise",
                   fn ->
                     TestRepo.insert(%MySchema{id: 1},
                       on_conflict: :raise,
                       conflict_target: [:id]
                     )
                   end
    end

    test "raises on query mismatch" do
      assert_raise ArgumentError, ~r"cannot run on_conflict: query", fn ->
        query = from(p in "posts")
        TestRepo.insert(%MySchema{id: 1}, on_conflict: query)
      end
    end
  end

  describe "preload" do
    test "returns nil if first argument of preload is nil" do
      assert TestRepo.preload(nil, []) == nil
    end

    test "raises if primary key is not defined" do
      query =
        from(p in MySchemaNoPK,
          left_join: c in MySchemaChild,
          on: p.n == p.n,
          preload: [child: c]
        )

      assert_raise Ecto.NoPrimaryKeyFieldError, fn ->
        TestRepo.all(query)
      end
    end

    test "raise if a combination query is used to preload a many association" do
      query = from(c in MySchemaChild)

      msg = ~r"`union` queries must be wrapped inside of a subquery"

      assert_raise ArgumentError, msg, fn ->
        TestRepo.preload(%MySchema{id: 1}, children: union(query, ^query))
      end

      msg = ~r"`union_all` queries must be wrapped inside of a subquery"

      assert_raise ArgumentError, msg, fn ->
        TestRepo.preload(%MySchema{id: 1}, children: union_all(query, ^query))
      end

      msg = ~r"`except` queries must be wrapped inside of a subquery"

      assert_raise ArgumentError, msg, fn ->
        TestRepo.preload(%MySchema{id: 1}, children: except(query, ^query))
      end

      msg = ~r"`except_all` queries must be wrapped inside of a subquery"

      assert_raise ArgumentError, msg, fn ->
        TestRepo.preload(%MySchema{id: 1}, children: except_all(query, ^query))
      end

      msg = ~r"`intersect` queries must be wrapped inside of a subquery"

      assert_raise ArgumentError, msg, fn ->
        TestRepo.preload(%MySchema{id: 1}, children: intersect(query, ^query))
      end

      msg = ~r"`intersect_all` queries must be wrapped inside of a subquery"

      assert_raise ArgumentError, msg, fn ->
        TestRepo.preload(%MySchema{id: 1}, children: intersect_all(query, ^query))
      end
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
      def cast("invalid"), do: :invalid
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

    test "invalid Ecto.Type.cast/1 implementation raises" do
      e =
        assert_raise RuntimeError, fn ->
          TestRepo.all(from s in MySchemaCustomPK, where: s.id == ^"invalid")
        end

      assert e.message =~ "expected Ecto.RepoTest.PrefixedID.cast/1 to return {:ok, v},"
    end
  end

  describe "transactions" do
    defmodule NoTransactionAdapter do
      @behaviour Ecto.Adapter
      defmacro __before_compile__(_opts), do: :ok
      def dumpers(_, _), do: raise("not implemented")
      def loaders(_, _), do: raise("not implemented")
      def init(_), do: raise("not implemented")
      def checkout(_, _, _), do: raise("not implemented")
      def checked_out?(_), do: raise("not implemented")
      def ensure_all_started(_, _), do: raise("not implemented")
    end

    defmodule NoTransactionRepo do
      use Ecto.Repo, otp_app: :ecto, adapter: NoTransactionAdapter
    end

    test "no transaction functions generated on repo without adapter support" do
      assert function_exported?(NoTransactionRepo, :config, 0)
      refute function_exported?(NoTransactionRepo, :transaction, 2)
      refute function_exported?(NoTransactionRepo, :transact, 2)
      refute function_exported?(NoTransactionRepo, :in_transaction?, 2)
      refute function_exported?(NoTransactionRepo, :rollback, 1)
    end
  end

  describe "dynamic repo" do
    setup config do
      {:ok, pid} = TestRepo.start_link(name: config.test)
      TestRepo = TestRepo.put_dynamic_repo(pid)
      :ok
    end

    test "puts the dynamic repo in pdict" do
      assert is_pid(TestRepo.get_dynamic_repo())

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

    test "keeps the proper repo in transact rollback", config do
      assert TestRepo.transact(fn -> {:error, :oops} end) == {:error, :oops}

      # Also check it works with named repos
      TestRepo.put_dynamic_repo(config.test)
      assert TestRepo.transact(fn -> {:error, :oops} end) == {:error, :oops}
    end

    test "keeps the proper repo in multi" do
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

      PrepareRepo.all(query, hello: :world)
      assert_received {:all, ^query, [hello: :world]}
      assert_received {:all, %{prefix: "rewritten"}}

      PrepareRepo.one(query, hello: :world)
      assert_received {:all, ^query, [hello: :world]}
      assert_received {:all, %{prefix: "rewritten"}}
    end

    test "update_all" do
      query = from p in MyParent, update: [set: [n: 1]]
      PrepareRepo.update_all(query, [], hello: :world)
      assert_received {:update_all, ^query, [hello: :world]}
      assert_received {:update_all, %{prefix: "rewritten"}}
    end

    test "delete_all" do
      query = from(p in MyParent)
      PrepareRepo.delete_all(query, hello: :world)
      assert_received {:delete_all, ^query, [hello: :world]}
      assert_received {:delete_all, %{prefix: "rewritten"}}
    end

    test "stream" do
      query = from p in MyParent, select: p
      PrepareRepo.stream(query, hello: :world) |> Enum.to_list()
      assert_received {:stream, ^query, _}
      assert_received {:stream, %{prefix: "rewritten"}}
    end

    test "preload" do
      PrepareRepo.preload(%MySchemaWithAssoc{parent_id: 1}, :parent, hello: :world)
      assert_received {:all, query, [ecto_query: :preload, hello: :world]}
      assert query.from.source == {"my_parent", Ecto.RepoTest.MyParent}
    end

    test "preload with :on_preloader_spawn" do
      test_process = self()
      fun = fn -> send(test_process, {:callback_ran, self()}) end

      %MySchemaWithMultiAssoc{parent_id: 1, mother_id: 2}
      |> PrepareRepo.preload([:parent, :mother], on_preloader_spawn: fun)

      assert_received {:callback_ran, pid1} when pid1 != self()
      assert_received {:callback_ran, pid2} when pid2 != self()
      assert pid1 != pid2
    end
  end

  describe "prepare_transaction" do
    defmodule PrepareTransactionRepo do
      use Ecto.Repo, otp_app: :ecto, adapter: Ecto.TestAdapter, stacktrace: true

      def prepare_transaction(fun_or_multi, opts) do
        send(self(), {:prepare_transaction, fun_or_multi, opts})
        {fun_or_multi, Keyword.put(opts, :commit_comment, "my_comment")}
      end
    end

    setup do
      _ = PrepareTransactionRepo.start_link(url: "ecto://user:pass@local/hello")
      :ok
    end

    test "transaction" do
      fun = fn -> :ok end
      opts = [commit_comment: "my_comment"]
      assert {:ok, :ok} = PrepareTransactionRepo.transaction(fun)
      assert_received {:prepare_transaction, _, _}
      assert_received {:transaction, _fun, ^opts}
    end
  end

  describe "transaction" do
    test "an arity zero function will be executed any it's value returned" do
      fun = fn -> :ok end
      assert {:ok, :ok} = TestRepo.transaction(fun)
      assert_received {:transaction, _, _}
    end

    test "an arity one function will be passed the repo as first argument" do
      fun = fn repo -> repo end

      assert {:ok, TestRepo} = TestRepo.transaction(fun)
      assert_received {:transaction, _, _}
    end
  end

  describe "all_running" do
    test "lists all running repositories" do
      assert Ecto.TestRepo in Ecto.Repo.all_running()
      pid = start_supervised!({Ecto.TestRepo, name: nil})
      assert pid in Ecto.Repo.all_running()
    end
  end

  describe "writable field option" do
    test "select" do
      TestRepo.all(from(w in MySchemaWritable, select: w))
      assert_receive {:all, query}

      assert query.select.fields == [
               {{:., [writable: :always], [{:&, [], [0]}, :id]}, [], []},
               {{:., [writable: :never], [{:&, [], [0]}, :never]}, [], []},
               {{:., [writable: :always], [{:&, [], [0]}, :always]}, [], []},
               {{:., [writable: :insert], [{:&, [], [0]}, :insert]}, [], []}
             ]
    end

    test "update only saves changes for writable: :always" do
      %MySchemaWritable{id: 1}
      |> Ecto.Changeset.change(%{always: 10, never: 11, insert: 12})
      |> TestRepo.update()

      assert_received {:update, %{changes: [always: 10]}}
    end

    test "update is a no-op when updatable fields are not changed" do
      %MySchemaWritable{id: 1}
      |> Ecto.Changeset.change(%{never: "can't update", insert: "can't update either"})
      |> TestRepo.update()

      refute_received {:update, _meta}
    end

    test "update with returning" do
      %MySchemaWritable{id: 1}
      |> Ecto.Changeset.change(%{always: 10, never: 11, insert: 12})
      |> TestRepo.update(returning: true)

      assert_received {:update, %{returning: returning}}
      assert Enum.sort(returning) == [:always, :id, :insert, :never]
    end

    test "update_all raises if non-updatable field is set" do
      update_query = from w in MySchemaWritable, update: [set: [never: 10]]

      assert_raise Ecto.QueryError, ~r/cannot update non-updatable field `:never` in query/, fn ->
        TestRepo.update_all(update_query, [])
      end

      update_query = from w in MySchemaWritable, update: [set: [insert: 10]]

      assert_raise Ecto.QueryError,
                   ~r/cannot update non-updatable field `:insert` in query/,
                   fn ->
                     TestRepo.update_all(update_query, [])
                   end
    end

    test "insert only saves changes for writable: :always/:insert" do
      %MySchemaWritable{id: 1}
      |> Ecto.Changeset.change(%{always: 10, never: 11, insert: 12})
      |> TestRepo.insert()

      assert_received {:insert, %{fields: inserted_fields}}
      assert Enum.sort(inserted_fields) == [always: 10, id: 1, insert: 12]
    end

    test "insert with returning" do
      %MySchemaWritable{id: 1}
      |> Ecto.Changeset.change(%{always: 10, never: 11, insert: 12})
      |> TestRepo.insert(returning: true)

      assert_received {:insert, %{fields: inserted_fields, returning: returning}}
      assert Enum.sort(inserted_fields) == [always: 10, id: 1, insert: 12]
      assert Enum.sort(returning) == [:always, :id, :insert, :never]
    end

    test "insert with on_conflict" do
      # conflict query
      on_conflict = from w in MySchemaWritable, update: [set: [insert: 10]]

      assert_raise Ecto.QueryError,
                   ~r/cannot update non-updatable field `:insert` in query/,
                   fn ->
                     TestRepo.insert(%MySchemaWritable{}, on_conflict: on_conflict)
                   end

      # conflict keyword
      assert_raise Ecto.QueryError, ~r/cannot update non-updatable field `:never` in query/, fn ->
        TestRepo.insert(%MySchemaWritable{}, on_conflict: [set: [never: 10]])
      end

      # conflict replace
      assert_raise ArgumentError,
                   ~r/cannot replace non-updatable field `:never` in :on_conflict option/,
                   fn ->
                     TestRepo.insert(%MySchemaWritable{},
                       on_conflict: {:replace, [:always, :never]}
                     )
                   end
    end

    test "insert with on_conflict = replace_all and returning" do
      TestRepo.insert!(%MySchemaWritable{always: 1, never: 2, insert: 3},
        on_conflict: :replace_all,
        returning: true
      )

      assert_received {:insert, %{fields: inserted_fields, returning: returning}}
      assert Enum.sort(inserted_fields) == [always: 1, insert: 3]
      assert Enum.sort(returning) == [:always, :id, :insert, :never]
    end

    test "insert_all" do
      # selecting maps
      msg = ~r/Unwritable fields, such as virtual and read only fields are not supported./

      assert_raise ArgumentError, msg, fn ->
        TestRepo.insert_all(MySchemaWritable, [%{always: 1, insert: 3, never: 2}])
      end

      # selecting individual fields
      msg = "cannot select unwritable field `:never` for insert_all"

      assert_raise ArgumentError, msg, fn ->
        query =
          from w in MySchemaWritable,
            select: %{always: w.always, insert: w.insert, never: w.insert}

        TestRepo.insert_all(MySchemaWritable, query)
      end

      # selecting sources
      msg = "cannot select unwritable field `:never` for insert_all"

      assert_raise ArgumentError, msg, fn ->
        query = from w in MySchemaWritable, select: w
        TestRepo.insert_all(MySchemaWritable, query)
      end
    end
  end

  defp select_fields(fields, ix) do
    for field <- fields do
      {{:., [writable: :always], [{:&, [], [ix]}, field]}, [], []}
    end
  end
end
