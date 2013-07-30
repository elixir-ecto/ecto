defmodule Ecto.Adapters.Postgres.SQLTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  alias Ecto.Adapters.Postgres.SQL

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
    query = from(Entity) |> select([r], r.x)
    assert SQL.select(query) == "SELECT e0.x\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x)
    assert SQL.select(query) == "SELECT e0.x\nFROM entity AS e0"

    query = from(Entity) |> from(Entity2) |> select([r1, r2], r2.x)
    assert SQL.select(query) == "SELECT e1.x\nFROM entity AS e0, entity2 AS e1"
  end

  test "select" do
    query = from(Entity) |> select([r], {r.x, r.y})
    assert SQL.select(query) == "SELECT e0.x, e0.y\nFROM entity AS e0"

    query = from(Entity) |> select([r], {r.x, r.y + 123})
    assert SQL.select(query) == "SELECT e0.x, e0.y + 123\nFROM entity AS e0"
  end

  test "where" do
    query = from(Entity) |> where([r], r.x != nil) |> select([r], r.x)
    assert SQL.select(query) == "SELECT e0.x\nFROM entity AS e0\nWHERE (e0.x IS NOT NULL)"

    query = from(Entity) |> where([r], r.x == 42) |> where([r], r.y != 43) |> select([r], r.x)
    assert SQL.select(query) == "SELECT e0.x\nFROM entity AS e0\nWHERE (e0.x = 42) AND (e0.y != 43)"
  end

  test "order by" do
    query = from(Entity) |> order_by([r], r.x) |> select([r], r.x)
    assert SQL.select(query) == "SELECT e0.x\nFROM entity AS e0\nORDER BY e0.x"

    query = from(Entity) |> order_by([r], [r.x, r.y]) |> select([r], r.x)
    assert SQL.select(query) == "SELECT e0.x\nFROM entity AS e0\nORDER BY e0.x, e0.y"

    query = from(Entity) |> order_by([r], [asc: r.x, desc: r.y]) |> select([r], r.x)
    assert SQL.select(query) == "SELECT e0.x\nFROM entity AS e0\nORDER BY e0.x ASC, e0.y DESC"
  end

  test "limit and offset" do
    query = from(Entity) |> limit([], 3) |> select([], 0)
    assert SQL.select(query) == "SELECT 0\nFROM entity AS e0\nLIMIT 3"

    query = from(Entity) |> offset([], 5) |> select([], 0)
    assert SQL.select(query) == "SELECT 0\nFROM entity AS e0\nOFFSET 5"

    query = from(Entity) |> offset([], 5) |> limit([], 3) |> select([], 0)
    assert SQL.select(query) == "SELECT 0\nFROM entity AS e0\nLIMIT 3\nOFFSET 5"
  end

  test "variable binding" do
    x = 123
    query = from(Entity) |> select([], x)
    assert SQL.select(query) == "SELECT 123\nFROM entity AS e0"

    query = from(Entity) |> select([r], x + r.y)
    assert SQL.select(query) == "SELECT 123 + e0.y\nFROM entity AS e0"
  end

  test "string escape" do
    x = "'\\ \n"
    query = from(Entity) |> select([], x)
    assert SQL.select(query) == "SELECT '''\\\\ \n'\nFROM entity AS e0"

    query = from(Entity) |> select([], "'\\")
    assert SQL.select(query) == "SELECT '''\\\\'\nFROM entity AS e0"
  end

  test "unary ops" do
    query = from(Entity) |> select([r], +r.x)
    assert SQL.select(query) == "SELECT +e0.x\nFROM entity AS e0"

    query = from(Entity) |> select([r], -r.x)
    assert SQL.select(query) == "SELECT -e0.x\nFROM entity AS e0"
  end

  test "binary ops" do
    query = from(Entity) |> select([r], r.x == 2)
    assert SQL.select(query) == "SELECT e0.x = 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x != 2)
    assert SQL.select(query) == "SELECT e0.x != 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x <= 2)
    assert SQL.select(query) == "SELECT e0.x <= 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x >= 2)
    assert SQL.select(query) == "SELECT e0.x >= 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x < 2)
    assert SQL.select(query) == "SELECT e0.x < 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x > 2)
    assert SQL.select(query) == "SELECT e0.x > 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x + 2)
    assert SQL.select(query) == "SELECT e0.x + 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x - 2)
    assert SQL.select(query) == "SELECT e0.x - 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x * 2)
    assert SQL.select(query) == "SELECT e0.x * 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x / 2)
    assert SQL.select(query) == "SELECT e0.x / 2\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x and false)
    assert SQL.select(query) == "SELECT e0.x AND FALSE\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x or false)
    assert SQL.select(query) == "SELECT e0.x OR FALSE\nFROM entity AS e0"
  end

  test "binary op null check" do
    query = from(Entity) |> select([r], r.x == nil)
    assert SQL.select(query) == "SELECT e0.x IS NULL\nFROM entity AS e0"

    query = from(Entity) |> select([r], nil == r.x)
    assert SQL.select(query) == "SELECT e0.x IS NULL\nFROM entity AS e0"

    query = from(Entity) |> select([r], r.x != nil)
    assert SQL.select(query) == "SELECT e0.x IS NOT NULL\nFROM entity AS e0"

    query = from(Entity) |> select([r], nil != r.x)
    assert SQL.select(query) == "SELECT e0.x IS NOT NULL\nFROM entity AS e0"
  end

  test "literals" do
    query = from(Entity) |> select([], nil)
    assert SQL.select(query) == "SELECT NULL\nFROM entity AS e0"

    query = from(Entity) |> select([], true)
    assert SQL.select(query) == "SELECT TRUE\nFROM entity AS e0"

    query = from(Entity) |> select([], false)
    assert SQL.select(query) == "SELECT FALSE\nFROM entity AS e0"

    query = from(Entity) |> select([], "abc")
    assert SQL.select(query) == "SELECT 'abc'\nFROM entity AS e0"

    query = from(Entity) |> select([], 123)
    assert SQL.select(query) == "SELECT 123\nFROM entity AS e0"

    query = from(Entity) |> select([], 123.0)
    assert SQL.select(query) == "SELECT 123.0\nFROM entity AS e0"
  end

  test "nested expressions" do
    z = 123
    query = from(r in Entity) |> select([r], r.x + (r.y + -z) - 3)
    assert SQL.select(query) == "SELECT (e0.x + (e0.y + -123)) - 3\nFROM entity AS e0"
  end

  test "use correct bindings" do
    query = from(r in Entity) |> select([not_r], not_r.x)
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
    query = from(SomeEntity, select: 0)
    assert SQL.select(query) == "SELECT 0\nFROM weird_name_123 AS w0"
  end

  test "update all" do
    assert SQL.update_all(Entity, [:e], x: 0) == "UPDATE entity AS e0\nSET x = 0"

    query = from(e in Entity, where: e.x == 123)
    assert SQL.update_all(query, [:e], x: 0) ==
           "UPDATE entity AS e0\nSET x = 0\nWHERE (e0.x = 123)"

    assert SQL.update_all(Entity, [:e], x: quote do e.x + 1 end) ==
           "UPDATE entity AS e0\nSET x = e0.x + 1"

    assert SQL.update_all(Entity, [:e], x: 0, y: "123") ==
           "UPDATE entity AS e0\nSET x = 0, y = '123'"
  end

  test "delete all" do
    assert SQL.delete_all(Entity) == "DELETE FROM entity AS e0"

    assert SQL.delete_all(from(e in Entity, where: e.x == 123)) ==
           "DELETE FROM entity AS e0\nWHERE (e0.x = 123)"
  end

  test "in expression" do
    query = from(Entity) |> select([e], 1 in [1,e.x,3])
    assert SQL.select(query) == "SELECT 1 = ANY (ARRAY[1, e0.x, 3])\nFROM entity AS e0"

    query = from(Entity) |> select([e], e.x in 1..3)
    assert SQL.select(query) == "SELECT e0.x BETWEEN 1 AND 3\nFROM entity AS e0"

    query = from(Entity) |> select([e], 1 in 1..(e.x + 5))
    assert SQL.select(query) == "SELECT 1 BETWEEN 1 AND e0.x + 5\nFROM entity AS e0"
  end

  test "list expression" do
    query = from(e in Entity) |> where([e], [e.x, e.y] == nil) |> select([e], 0)
    assert SQL.select(query) == "SELECT 0\nFROM entity AS e0\nWHERE (ARRAY[e0.x, e0.y] IS NULL)"
  end

  test "unbound vars" do
    query = from(Entity) |> from(Entity2) |> select([_, b], b.z)
    assert SQL.select(query) == "SELECT e1.z\nFROM entity AS e0, entity2 AS e1"

    query = from(Entity) |> from(Entity2) |> select([a, _], a.x)
    assert SQL.select(query) == "SELECT e0.x\nFROM entity AS e0, entity2 AS e1"

    query = from(Entity) |> from(Entity2) |> select([_, _], 0)
    assert SQL.select(query) == "SELECT 0\nFROM entity AS e0, entity2 AS e1"
  end
end
