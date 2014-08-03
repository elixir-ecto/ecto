defmodule Ecto.Adapters.Mysql.SQLTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto.Query.Normalizer, only: [normalize: 1]
  alias Ecto.Adapters.Mysql.SQL
  alias Ecto.Queryable

  defmodule Model do
    use Ecto.Model

    schema "model" do
      field :x, :integer
      field :y, :integer
    end
  end

  defmodule Model2 do
    use Ecto.Model
    schema "model2" do
      field :z, :integer
    end
  end

  defmodule Model3 do
    use Ecto.Model

    schema "model3" do
      field :list1, {:array, :string}
      field :list2, {:array, :integer}
      field :binary, :binary
    end
  end

  defmodule SomeModel do
    use Ecto.Model

    schema "weird_name_123" do
    end
  end

  test "from" do
    query = Model |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\"\nFROM \"model\" AS m0"
  end

  test "from without model" do
    query = "posts" |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT p0.\"x\"\nFROM \"posts\" AS p0"
  end

  test "select" do
    query = Model |> select([r], {r.x, r.y}) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\", m0.\"y\"\nFROM \"model\" AS m0"

    query = Model |> select([r], {r.x, r.y + 123}) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\", m0.\"y\" + 123\nFROM \"model\" AS m0"
  end

  test "distinct" do
    query = Model |> distinct([r], r.x) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.select(query) == "SELECT DISTINCT ON (m0.\"x\") m0.\"x\", m0.\"y\"\nFROM \"model\" AS m0"

    query = Model |> distinct([r], 2 * 2) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT DISTINCT ON (2 * 2) m0.\"x\"\nFROM \"model\" AS m0"

    query = Model |> distinct([r], [r.x, r.y]) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.select(query) == "SELECT DISTINCT ON (m0.\"x\", m0.\"y\") m0.\"x\", m0.\"y\"\nFROM \"model\" AS m0"
  end

  test "where" do
    query = Model |> where([r], r.x != nil) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\"\nFROM \"model\" AS m0\nWHERE (m0.\"x\" IS NOT NULL)"

    query = Model |> where([r], r.x == 42) |> where([r], r.y != 43) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\"\nFROM \"model\" AS m0\nWHERE (m0.\"x\" = 42) AND (m0.\"y\" != 43)"
  end

  test "order by" do
    query = Model |> order_by([r], r.x) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\"\nFROM \"model\" AS m0\nORDER BY m0.\"x\""

    query = Model |> order_by([r], 2 * 2) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\"\nFROM \"model\" AS m0\nORDER BY 2 * 2"

    query = Model |> order_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\"\nFROM \"model\" AS m0\nORDER BY m0.\"x\", m0.\"y\""

    query = Model |> order_by([r], [asc: r.x, desc: r.y]) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\"\nFROM \"model\" AS m0\nORDER BY m0.\"x\", m0.\"y\" DESC"
  end

  test "limit and offset" do
    query = Model |> limit(3) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM \"model\" AS m0\nLIMIT 3"

    query = Model |> offset(5) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM \"model\" AS m0\nOFFSET 5"

    query = Model |> offset(5) |> limit(3) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM \"model\" AS m0\nLIMIT 3\nOFFSET 5"
  end

  test "lock" do
    query = Model |> lock(true) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM \"model\" AS m0\nFOR UPDATE"

    query = Model |> lock("FOR SHARE NOWAIT") |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM \"model\" AS m0\nFOR SHARE NOWAIT"
  end

  test "variable binding" do
    x = 123
    query = Model |> select([], ^x) |> normalize
    assert SQL.select(query) == "SELECT 123\nFROM \"model\" AS m0"

    query = Model |> select([r], ^x + r.y) |> normalize
    assert SQL.select(query) == "SELECT 123 + m0.\"y\"\nFROM \"model\" AS m0"
  end

  test "string escape" do
    x = "'\\ \n"
    query = Model |> select([], ^x) |> normalize
    assert SQL.select(query) == "SELECT '''\\ \n'\nFROM \"model\" AS m0"

    query = Model |> select([], "'") |> normalize
    assert SQL.select(query) == "SELECT ''''\nFROM \"model\" AS m0"
  end

  test "unary ops" do
    query = Model |> select([r], +r.x) |> normalize
    assert SQL.select(query) == "SELECT +m0.\"x\"\nFROM \"model\" AS m0"

    query = Model |> select([r], -r.x) |> normalize
    assert SQL.select(query) == "SELECT -m0.\"x\"\nFROM \"model\" AS m0"
  end

  test "binary ops" do
    query = Model |> select([r], r.x == 2) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\" = 2\nFROM \"model\" AS m0"

    query = Model |> select([r], r.x != 2) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\" != 2\nFROM \"model\" AS m0"

    query = Model |> select([r], r.x <= 2) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\" <= 2\nFROM \"model\" AS m0"

    query = Model |> select([r], r.x >= 2) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\" >= 2\nFROM \"model\" AS m0"

    query = Model |> select([r], r.x < 2) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\" < 2\nFROM \"model\" AS m0"

    query = Model |> select([r], r.x > 2) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\" > 2\nFROM \"model\" AS m0"

    query = Model |> select([r], r.x + 2) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\" + 2\nFROM \"model\" AS m0"

    query = Model |> select([r], r.x - 2) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\" - 2\nFROM \"model\" AS m0"

    query = Model |> select([r], r.x * 2) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\" * 2\nFROM \"model\" AS m0"

    query = Model |> select([r], r.x / 2) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\" / 2::numeric\nFROM \"model\" AS m0"

    query = Model |> select([r], r.x and false) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\" AND FALSE\nFROM \"model\" AS m0"

    query = Model |> select([r], r.x or false) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\" OR FALSE\nFROM \"model\" AS m0"
  end

  test "binary op null check" do
    query = Model |> select([r], r.x == nil) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\" IS NULL\nFROM \"model\" AS m0"

    query = Model |> select([r], nil == r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\" IS NULL\nFROM \"model\" AS m0"

    query = Model |> select([r], r.x != nil) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\" IS NOT NULL\nFROM \"model\" AS m0"

    query = Model |> select([r], nil != r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\" IS NOT NULL\nFROM \"model\" AS m0"
  end

  test "literals" do
    query = Model |> select([], nil) |> normalize
    assert SQL.select(query) == "SELECT NULL\nFROM \"model\" AS m0"

    query = Model |> select([], true) |> normalize
    assert SQL.select(query) == "SELECT TRUE\nFROM \"model\" AS m0"

    query = Model |> select([], false) |> normalize
    assert SQL.select(query) == "SELECT FALSE\nFROM \"model\" AS m0"

    query = Model |> select([], "abc") |> normalize
    assert SQL.select(query) == "SELECT 'abc'\nFROM \"model\" AS m0"

    query = Model |> select([], <<?a,?b,?c>>) |> normalize
    assert SQL.select(query) == "SELECT 'abc'\nFROM \"model\" AS m0"

    query = Model |> select([], binary(<<0,1,2>>)) |> normalize
    assert SQL.select(query) == "SELECT '\\x000102'::bytea\nFROM \"model\" AS m0"

    query = Model |> select([], 123) |> normalize
    assert SQL.select(query) == "SELECT 123\nFROM \"model\" AS m0"

    query = Model |> select([], 123.0) |> normalize
    assert SQL.select(query) == "SELECT 123.0::float\nFROM \"model\" AS m0"

    query = Model |> select([], ^Decimal.new("42")) |> normalize
    assert SQL.select(query) == "SELECT 42.0\nFROM \"model\" AS m0"

    query = Model |> select([], ^%Ecto.DateTime{year: 2014, month: 1, day: 16, hour: 20, min: 26, sec: 51}) |> normalize
    assert SQL.select(query) == "SELECT timestamp '2014-1-16 20:26:51'\nFROM \"model\" AS m0"

    query = Model |> select([], ^%Ecto.Interval{year: 2014, month: 1, day: 16, hour: 20, min: 26, sec: 51}) |> normalize
    assert SQL.select(query) == "SELECT interval 'P2014-1-16T20:26:51'\nFROM \"model\" AS m0"
  end

  test "nested expressions" do
    z = 123
    query = from(r in Model, []) |> select([r], r.x + (r.y + ^(-z)) - 3) |> normalize
    assert SQL.select(query) == "SELECT (m0.\"x\" + (m0.\"y\" + -123)) - 3\nFROM \"model\" AS m0"
  end

  test "use correct bindings" do
    query = from(r in Model, []) |> select([not_r], not_r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\"\nFROM \"model\" AS m0"
  end

  test "insert" do
    query = SQL.insert(%Model{x: 123, y: "456"}, [:id])
    assert query == "INSERT INTO \"model\" (\"x\", \"y\")\nVALUES (123, '456')\nRETURNING \"id\""
  end

  test "insert with missing values" do
    query = SQL.insert(%Model{x: 123}, [:id, :y])
    assert query == "INSERT INTO \"model\" (\"x\")\nVALUES (123)\nRETURNING \"id\", \"y\""

    query = SQL.insert(%Model{}, [:id, :y])
    assert query == "INSERT INTO \"model\" DEFAULT VALUES\nRETURNING \"id\", \"y\""
  end

  test "insert with list" do
    query = SQL.insert(%Model3{list1: %Ecto.Tagged{value: ["a", "b", "c"], type: {:array, :string}}, list2: %Ecto.Tagged{value: [1, 2, 3], type: {:array, :integer}}}, [:id])
    assert query == "INSERT INTO \"model3\" (\"list1\", \"list2\")\nVALUES (ARRAY['a', 'b', 'c']::text[], ARRAY[1, 2, 3]::integer[])\nRETURNING \"id\""
  end

  test "insert with binary" do
    query = SQL.insert(%Model3{binary: %Ecto.Tagged{value: << 1, 2, 3 >>, type: :binary}}, [:id])
    assert query == "INSERT INTO \"model3\" (\"binary\")\nVALUES ('\\x010203'::bytea)\nRETURNING \"id\""
  end

  test "update" do
    query = SQL.update(%Model{id: 42, x: 123, y: "456"})
    assert query == "UPDATE \"model\" SET \"x\" = 123, \"y\" = '456'\nWHERE \"id\" = 42"
  end

  test "update with list" do
    query = SQL.update(%Model3{id: 42, list1: %Ecto.Tagged{value: ["c", "d"], type: {:array, :string}}, list2: %Ecto.Tagged{value: [4, 5], type: {:array, :integer}}})
    assert query == "UPDATE \"model3\" SET \"binary\" = NULL, \"list1\" = ARRAY['c', 'd']::text[], \"list2\" = ARRAY[4, 5]::integer[]\nWHERE \"id\" = 42"
  end

  test "update with binary" do
    query = SQL.update(%Model3{id: 42, binary: %Ecto.Tagged{value: << 1, 2, 3 >>, type: :binary}})
    assert query == "UPDATE \"model3\" SET \"binary\" = '\\x010203'::bytea, \"list1\" = NULL, \"list2\" = NULL\nWHERE \"id\" = 42"
  end

  test "delete" do
    query = SQL.delete(%Model{id: 42, x: 123, y: "456"})
    assert query == "DELETE FROM \"model\" WHERE \"id\" = 42"
  end

  test "table name" do
    query = from(SomeModel, select: 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM \"weird_name_123\" AS w0"
  end

  test "update all" do
    query = Model |> Queryable.to_query |> normalize
    assert SQL.update_all(query, x: 0) == "UPDATE \"model\" AS m0\nSET \"x\" = 0"

    query = from(e in Model, where: e.x == 123) |> normalize
    assert SQL.update_all(query, x: 0) ==
           "UPDATE \"model\" AS m0\nSET \"x\" = 0\nWHERE (m0.\"x\" = 123)"

    query = Model |> Queryable.to_query |> normalize
    assert SQL.update_all(query, x: quote do &0.x + 1 end) ==
           "UPDATE \"model\" AS m0\nSET \"x\" = m0.\"x\" + 1"

    query = Model |> Queryable.to_query |> normalize
    assert SQL.update_all(query, x: 0, y: "123") ==
           "UPDATE \"model\" AS m0\nSET \"x\" = 0, \"y\" = '123'"
  end

  test "delete all" do
    query = Model |> Queryable.to_query |> normalize
    assert SQL.delete_all(query) == "DELETE FROM \"model\" AS m0"

    query = from(e in Model, where: e.x == 123) |> normalize
    assert SQL.delete_all(query) ==
           "DELETE FROM \"model\" AS m0\nWHERE (m0.\"x\" = 123)"
  end

  test "in expression" do
    query = Model |> select([e], 1 in array([1,e.x,3], ^:integer)) |> normalize
    assert SQL.select(query) == "SELECT 1 = ANY (ARRAY[1, m0.\"x\", 3])\nFROM \"model\" AS m0"

    query = Model |> select([e], e.x in 1..3) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\" BETWEEN 1 AND 3\nFROM \"model\" AS m0"

    query = Model |> select([e], 1 in 1..(e.x + 5)) |> normalize
    assert SQL.select(query) == "SELECT 1 BETWEEN 1 AND m0.\"x\" + 5\nFROM \"model\" AS m0"
  end

  test "list expression" do
    query = from(e in Model, []) |> where([e], array([], ^:integer) == nil) |> select([e], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM \"model\" AS m0\nWHERE (ARRAY[]::integer[] IS NULL)"

    query = from(e in Model, []) |> where([e], array([e.x, e.y], ^:integer) == nil) |> select([e], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM \"model\" AS m0\nWHERE (ARRAY[m0.\"x\", m0.\"y\"] IS NULL)"
  end

  test "having" do
    query = Model |> having([p], p.x == p.x) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM \"model\" AS m0\nHAVING (m0.\"x\" = m0.\"x\")"

    query = Model |> having([p], p.x == p.x) |> having([p], p.y == p.y) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM \"model\" AS m0\nHAVING (m0.\"x\" = m0.\"x\") AND (m0.\"y\" = m0.\"y\")"
  end

  test "group by" do
    query = Model |> group_by([r], r.x) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\"\nFROM \"model\" AS m0\nGROUP BY m0.\"x\""

    query = Model |> group_by([r], 2 * 2) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\"\nFROM \"model\" AS m0\nGROUP BY 2 * 2"

    query = Model |> group_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\"\nFROM \"model\" AS m0\nGROUP BY m0.\"x\", m0.\"y\""
  end

  test "sigils" do
    query = Model |> select([], ~s"abc" in array(~w(abc def), ^:string)) |> normalize
    assert SQL.select(query) == "SELECT 'abc' = ANY (ARRAY['abc', 'def'])\nFROM \"model\" AS m0"
  end

  defmodule Rec, do: defstruct [:x]

  defp fun(x), do: x+x

  test "query interpolation" do
    r = %Rec{x: 123}
    query = Model |> select([r], r.x + ^(1 + 2 + 3) + ^r.x) |> normalize
    assert SQL.select(query) == "SELECT (m0.\"x\" + 6) + 123\nFROM \"model\" AS m0"

    query = Model |> select([r], r.x + ^fun(r.x)) |> normalize
    assert SQL.select(query) == "SELECT m0.\"x\" + 246\nFROM \"model\" AS m0"
  end

  test "functions" do
    query = Model |> select([], random()) |> normalize
    assert SQL.select(query) == "SELECT random()\nFROM \"model\" AS m0"

    query = Model |> select([], round(12.34)) |> normalize
    assert SQL.select(query) == "SELECT round(12.34::float)\nFROM \"model\" AS m0"

    query = Model |> select([], round(12.34, 1)) |> normalize
    assert SQL.select(query) == "SELECT round(12.34::float, 1)\nFROM \"model\" AS m0"

    query = Model |> select([], pow(7, 2)) |> normalize
    assert SQL.select(query) == "SELECT 7 ^ 2\nFROM \"model\" AS m0"
  end

  test "join" do
    query = Model |> join(:inner, [p], q in Model2, p.x == q.z) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM \"model\" AS m0\nINNER JOIN \"model2\" AS m1 ON m0.\"x\" = m1.\"z\""

    query = Model |> join(:inner, [p], q in Model2, p.x == q.z) |> join(:inner, [], Model, true) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM \"model\" AS m0\nINNER JOIN \"model2\" AS m1 ON m0.\"x\" = m1.\"z\"\n" <>
      "INNER JOIN \"model\" AS m2 ON TRUE"
  end

  test "join with nothing bound" do
    query = Model |> join(:inner, [], q in Model2, q.z == q.z) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM \"model\" AS m0\nINNER JOIN \"model2\" AS m1 ON m1.\"z\" = m1.\"z\""
  end

  test "join without model" do
    query = "posts" |> join(:inner, [p], q in "comments", p.x == q.z) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM \"posts\" AS p0\nINNER JOIN \"comments\" AS c0 ON p0.\"x\" = c0.\"z\""
  end

  defmodule Comment do
    use Ecto.Model

    schema "comments" do
      belongs_to :post, Ecto.Adapters.Postgres.SQLTest.Post,
        references: :a,
        foreign_key: :b
    end
  end

  defmodule Post do
    use Ecto.Model

    schema "posts" do
      has_many :comments, Ecto.Adapters.Postgres.SQLTest.Comment,
        references: :c,
        foreign_key: :d
      has_one :permalink, Ecto.Adapters.Postgres.SQLTest.Permalink,
        references: :e,
        foreign_key: :f
      field :c, :integer
      field :e, :integer
    end
  end

  defmodule Permalink do
    use Ecto.Model
    schema "permalinks" do
    end
  end

  test "association join belongs_to" do
    query = Comment |> join(:inner, [c], p in c.post) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM \"comments\" AS c0\nINNER JOIN \"posts\" AS p0 ON p0.\"a\" = c0.\"b\""
  end

  test "association join has_many" do
    query = Post |> join(:inner, [p], c in p.comments) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM \"posts\" AS p0\nINNER JOIN \"comments\" AS c0 ON c0.\"d\" = p0.\"c\""
  end

  test "association join has_one" do
    query = Post |> join(:inner, [p], pp in p.permalink) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM \"posts\" AS p0\nINNER JOIN \"permalinks\" AS p1 ON p1.\"f\" = p0.\"e\""
  end

  test "association join with on" do
    query = Post |> join(:inner, [p], c in p.comments, 1 == 2) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM \"posts\" AS p0\nINNER JOIN \"comments\" AS c0 ON (1 = 2) AND (c0.\"d\" = p0.\"c\")"
  end

  test "join produces correct bindings" do
    query = from(p in Post, join: c in Comment, on: true)
    query = from(p in query, join: c in Comment, on: true, select: {p.id, c.id})
    query = normalize(query)
    assert SQL.select(query) == ~s'SELECT p0."id", c1."id"\nFROM "posts" AS p0\nINNER JOIN "comments" AS c0 ON TRUE\nINNER JOIN "comments" AS c1 ON TRUE'
  end

  defmodule PKModel do
    use Ecto.Model

    schema "model", primary_key: false do
      field :x, :integer
      field :pk, :integer, primary_key: true
      field :y, :integer
    end
  end

  test "primary key any location" do
    model = %PKModel{x: 10, y: 30}
    assert SQL.insert(model, [:pk]) == "INSERT INTO \"model\" (\"x\", \"y\")\nVALUES (10, 30)\nRETURNING \"pk\""

    model = %PKModel{x: 10, pk: 20, y: 30}
    assert SQL.insert(model, []) == "INSERT INTO \"model\" (\"pk\", \"x\", \"y\")\nVALUES (20, 10, 30)"
  end

  test "send explicit set primary key" do
    model = %Model{id: 123, x: 0, y: 2}
    assert SQL.insert(model, []) == "INSERT INTO \"model\" (\"id\", \"x\", \"y\")\nVALUES (123, 0, 2)"
  end
end
