defmodule Ecto.Adapters.Postgres.SQLTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto.Query.Util, only: [normalize: 1]
  alias Ecto.Adapters.Postgres.SQL
  alias Ecto.Queryable

  defmodule Entity do
    use Ecto.Entity

    dataset "entity" do
      field :x, :integer
      field :y, :integer
    end
  end

  defmodule Entity2 do
    use Ecto.Entity
    dataset "entity2" do
      field :z, :integer
    end
  end

  defmodule SomeEntity do
    use Ecto.Entity

    dataset "weird_name_123" do
    end
  end

  test "from" do
    query = from(Entity) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT e0.x\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT e0.x\nFROM entity AS e0"
  end

  test "select" do
    query = from(Entity) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.select(query) == "SELECT e0.x, e0.y\nFROM entity AS e0"

    query = from(Entity) |> select([r], {r.x, r.y + 123}) |> normalize
    assert SQL.select(query) == "SELECT e0.x, e0.y + 123\nFROM entity AS e0"
  end

  test "where" do
    query = from(Entity) |> where([r], r.x != nil) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT e0.x\nFROM entity AS e0\nWHERE (e0.x IS NOT NULL)"

    query = from(Entity) |> where([r], r.x == 42) |> where([r], r.y != 43) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT e0.x\nFROM entity AS e0\nWHERE (e0.x = 42) AND (e0.y != 43)"
  end

  test "order by" do
    query = from(Entity) |> order_by([r], r.x) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT e0.x\nFROM entity AS e0\nORDER BY e0.x"

    query = from(Entity) |> order_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT e0.x\nFROM entity AS e0\nORDER BY e0.x, e0.y"

    query = from(Entity) |> order_by([r], [asc: r.x, desc: r.y]) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT e0.x\nFROM entity AS e0\nORDER BY e0.x ASC, e0.y DESC"
  end

  test "limit and offset" do
    query = from(Entity) |> limit([], 3) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM entity AS e0\nLIMIT 3"

    query = from(Entity) |> offset([], 5) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM entity AS e0\nOFFSET 5"

    query = from(Entity) |> offset([], 5) |> limit([], 3) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM entity AS e0\nLIMIT 3\nOFFSET 5"
  end

  test "variable binding" do
    x = 123
    query = from(Entity) |> select([], ^x) |> normalize
    assert SQL.select(query) == "SELECT 123\nFROM entity AS e0"

    query = from(Entity) |> select([r], ^x + r.y) |> normalize
    assert SQL.select(query) == "SELECT 123 + e0.y\nFROM entity AS e0"
  end

  test "string escape" do
    x = "'\\ \n"
    query = from(Entity) |> select([], ^x) |> normalize
    assert SQL.select(query) == "SELECT '''\\\\ \n'\nFROM entity AS e0"

    query = from(Entity) |> select([], "'\\") |> normalize
    assert SQL.select(query) == "SELECT '''\\\\'\nFROM entity AS e0"
  end

  test "unary ops" do
    query = from(Entity) |> select([r], +r.x) |> normalize
    assert SQL.select(query) == "SELECT +e0.x\nFROM entity AS e0"

    query = from(Entity) |> select([r], -r.x) |> normalize
    assert SQL.select(query) == "SELECT -e0.x\nFROM entity AS e0"
  end

  test "binary ops" do
    query = from(Entity) |> select([r], r.x == 2) |> normalize
    assert SQL.select(query) == "SELECT e0.x = 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x != 2) |> normalize
    assert SQL.select(query) == "SELECT e0.x != 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x <= 2) |> normalize
    assert SQL.select(query) == "SELECT e0.x <= 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x >= 2) |> normalize
    assert SQL.select(query) == "SELECT e0.x >= 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x < 2) |> normalize
    assert SQL.select(query) == "SELECT e0.x < 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x > 2) |> normalize
    assert SQL.select(query) == "SELECT e0.x > 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x + 2) |> normalize
    assert SQL.select(query) == "SELECT e0.x + 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x - 2) |> normalize
    assert SQL.select(query) == "SELECT e0.x - 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x * 2) |> normalize
    assert SQL.select(query) == "SELECT e0.x * 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x / 2) |> normalize
    assert SQL.select(query) == "SELECT e0.x / 2::float\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x and false) |> normalize
    assert SQL.select(query) == "SELECT e0.x AND FALSE\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x or false) |> normalize
    assert SQL.select(query) == "SELECT e0.x OR FALSE\nFROM entity AS e0"
  end

  test "binary op null check" do
    query = from(Entity) |> select([r], r.x == nil) |> normalize
    assert SQL.select(query) == "SELECT e0.x IS NULL\nFROM entity AS e0"

    query = from(Entity) |> select([r], nil == r.x) |> normalize
    assert SQL.select(query) == "SELECT e0.x IS NULL\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x != nil) |> normalize
    assert SQL.select(query) == "SELECT e0.x IS NOT NULL\nFROM entity AS e0"

    query = from(Entity) |> select([r], nil != r.x) |> normalize
    assert SQL.select(query) == "SELECT e0.x IS NOT NULL\nFROM entity AS e0"
  end

  test "literals" do
    query = from(Entity) |> select([], nil) |> normalize
    assert SQL.select(query) == "SELECT NULL\nFROM entity AS e0"

    query = from(Entity) |> select([], true) |> normalize
    assert SQL.select(query) == "SELECT TRUE\nFROM entity AS e0"

    query = from(Entity) |> select([], false) |> normalize
    assert SQL.select(query) == "SELECT FALSE\nFROM entity AS e0"

    query = from(Entity) |> select([], "abc") |> normalize
    assert SQL.select(query) == "SELECT 'abc'\nFROM entity AS e0"

    query = from(Entity) |> select([], 123) |> normalize
    assert SQL.select(query) == "SELECT 123\nFROM entity AS e0"

    query = from(Entity) |> select([], 123.0) |> normalize
    assert SQL.select(query) == "SELECT 123.0\nFROM entity AS e0"
  end

  test "nested expressions" do
    z = 123
    query = from(r in Entity) |> select([r], r.x + (r.y + ^(-z)) - 3) |> normalize
    assert SQL.select(query) == "SELECT (e0.x + (e0.y + -123)) - 3\nFROM entity AS e0"
  end

  test "use correct bindings" do
    query = from(r in Entity) |> select([not_r], not_r.x) |> normalize
    assert SQL.select(query) == "SELECT e0.x\nFROM entity AS e0"
  end

  test "insert" do
    query = SQL.insert(Entity[x: 123, y: "456"])
    assert query == "INSERT INTO entity (x, y)\nVALUES (123, '456')\nRETURNING id"
  end

  test "update" do
    query = SQL.update(Entity[id: 42, x: 123, y: "456"])
    assert query == "UPDATE entity SET x = 123, y = '456'\nWHERE id = 42"
  end

  test "delete" do
    query = SQL.delete(Entity[id: 42, x: 123, y: "456"])
    assert query == "DELETE FROM entity WHERE id = 42"
  end

  test "table name" do
    query = from(SomeEntity, select: 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM weird_name_123 AS w0"
  end

  test "update all" do
    query = Entity |> Queryable.to_query |> normalize
    assert SQL.update_all(query, x: 0) == "UPDATE entity AS e0\nSET x = 0"

    query = from(e in Entity, where: e.x == 123) |> normalize
    assert SQL.update_all(query, x: 0) ==
           "UPDATE entity AS e0\nSET x = 0\nWHERE (e0.x = 123)"

    query = Entity |> Queryable.to_query |> normalize
    assert SQL.update_all(query, x: quote do &0.x + 1 end) ==
           "UPDATE entity AS e0\nSET x = e0.x + 1"

    query = Entity |> Queryable.to_query |> normalize
    assert SQL.update_all(query, x: 0, y: "123") ==
           "UPDATE entity AS e0\nSET x = 0, y = '123'"
  end

  test "delete all" do
    query = Entity |> Queryable.to_query |> normalize
    assert SQL.delete_all(query) == "DELETE FROM entity AS e0"

    query = from(e in Entity, where: e.x == 123) |> normalize
    assert SQL.delete_all(query) ==
           "DELETE FROM entity AS e0\nWHERE (e0.x = 123)"
  end

  test "in expression" do
    query = from(Entity) |> select([e], 1 in [1,e.x,3]) |> normalize
    assert SQL.select(query) == "SELECT 1 = ANY (ARRAY[1, e0.x, 3])\nFROM entity AS e0"

    query = from(Entity) |> select([e], e.x in 1..3) |> normalize
    assert SQL.select(query) == "SELECT e0.x BETWEEN 1 AND 3\nFROM entity AS e0"

    query = from(Entity) |> select([e], 1 in 1..(e.x + 5)) |> normalize
    assert SQL.select(query) == "SELECT 1 BETWEEN 1 AND e0.x + 5\nFROM entity AS e0"
  end

  test "list expression" do
    query = from(e in Entity) |> where([e], [e.x, e.y] == nil) |> select([e], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM entity AS e0\nWHERE (ARRAY[e0.x, e0.y] IS NULL)"
  end

  test "having" do
    query = from(Entity) |> having([p], p.x == p.x) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM entity AS e0\nHAVING (e0.x = e0.x)"

    query = from(Entity) |> having([p], p.x == p.x) |> having([p], p.y == p.y) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM entity AS e0\nHAVING (e0.x = e0.x) AND (e0.y = e0.y)"
  end

  test "group by" do
    query = from(Entity) |> group_by([r], r.x) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT e0.x\nFROM entity AS e0\nGROUP BY e0.x"

    query = from(Entity) |> group_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT e0.x\nFROM entity AS e0\nGROUP BY e0.x, e0.y"
  end

  defrecord Rec, [:x]

  defp fun(x), do: x+x

  test "query interpolation" do
    r = Rec[x: 123]
    query = from(Entity) |> select([r], r.x + ^(1 + 2 + 3) + ^r.x) |> normalize
    assert SQL.select(query) == "SELECT (e0.x + 6) + 123\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x + ^fun(r.x)) |> normalize
    assert SQL.select(query) == "SELECT e0.x + 246\nFROM entity AS e0"
  end

  test "functions" do
    query = from(Entity) |> select([], random()) |> normalize
    assert SQL.select(query) == "SELECT random()\nFROM entity AS e0"

    query = from(Entity) |> select([], round(12.34)) |> normalize
    assert SQL.select(query) == "SELECT round(12.34)\nFROM entity AS e0"

    query = from(Entity) |> select([], round(12.34, 1)) |> normalize
    assert SQL.select(query) == "SELECT round(12.34, 1)\nFROM entity AS e0"

    query = from(Entity) |> select([], pow(7, 2)) |> normalize
    assert SQL.select(query) == "SELECT 7 ^ 2\nFROM entity AS e0"
  end

  test "join" do
    query = from(Entity) |> join([p], nil, q in Entity2, p.x == q.z) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM entity AS e0\nJOIN entity2 AS e1 ON e0.x = e1.z"

    query = from(Entity) |> join([p], :inner, q in Entity2, p.x == q.z) |> join([], nil, Entity, true) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM entity AS e0\nINNER JOIN entity2 AS e1 ON e0.x = e1.z\n" <>
      "JOIN entity AS e2 ON TRUE"
  end

  defmodule Comment do
    use Ecto.Entity

    dataset "comments" do
      belongs_to :post, Ecto.Adapters.Postgres.SQLTest.Post
    end
  end

  defmodule Post do
    use Ecto.Entity

    dataset "posts" do
      has_many :comments, Ecto.Adapters.Postgres.SQLTest.Comment
    end
  end

  defmodule PKEntity do
    use Ecto.Entity

    dataset "entity", nil do
      field :x, :integer
      field :pk, :integer, primary_key: true
      field :y, :integer
    end
  end

  test "primary key any location" do
    entity = PKEntity[x: 10, y: 30]
    assert SQL.insert(entity) == "INSERT INTO entity (x, y)\nVALUES (10, 30)\nRETURNING pk"

    entity = PKEntity[x: 10, pk: 20, y: 30]
    assert SQL.insert(entity) == "INSERT INTO entity (x, pk, y)\nVALUES (10, 20, 30)"
  end

  test "send explicit set primary key" do
    entity = Entity[id: 123, x: 0, y: 1]
    assert SQL.insert(entity) == "INSERT INTO entity (id, x, y)\nVALUES (123, 0, 1)"
  end
end
