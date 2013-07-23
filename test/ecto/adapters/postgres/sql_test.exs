Code.require_file "../../../test_helper.exs", __DIR__

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
    end
  end

  defmodule SomeEntity do
    use Ecto.Entity

    dataset "weird_name_123" do
    end
  end

  test "from" do
    query = from(r in Entity) |> select([r], r.x)
    assert SQL.select(query) == "SELECT entity.x\nFROM entity"

    query = from(r in Entity) |> from(r2 in Entity2) |> select([r], r.x)
    assert SQL.select(query) == "SELECT entity.x\nFROM entity, entity2"
  end

  test "select" do
    query = from(r in Entity) |> select([r], {r.x, r.y})
    assert SQL.select(query) == "SELECT entity.x, entity.y\nFROM entity"

    query = from(r in Entity) |> select([r], {r.x, r.y + 123})
    assert SQL.select(query) == "SELECT entity.x, entity.y + 123\nFROM entity"
  end

  test "where" do
    query = from(r in Entity) |> where([r], r.x != nil) |> select([r], r.x)
    assert SQL.select(query) == "SELECT entity.x\nFROM entity\nWHERE (entity.x IS NOT NULL)"

    query = from(r in Entity) |> where([r], r.x == 42) |> where([r], r.y != 43) |> select([r], r.x)
    assert SQL.select(query) == "SELECT entity.x\nFROM entity\nWHERE (entity.x = 42) AND (entity.y != 43)"
  end

  test "order by" do
    query = from(r in Entity) |> order_by([r], r.x) |> select([r], r.x)
    assert SQL.select(query) == "SELECT entity.x\nFROM entity\nORDER BY entity.x"

    query = from(r in Entity) |> order_by([r], [r.x, r.y]) |> select([r], r.x)
    assert SQL.select(query) == "SELECT entity.x\nFROM entity\nORDER BY entity.x, entity.y"

    query = from(r in Entity) |> order_by([r], [asc: r.x, desc: r.y]) |> select([r], r.x)
    assert SQL.select(query) == "SELECT entity.x\nFROM entity\nORDER BY entity.x ASC, entity.y DESC"
  end

  test "limit and offset" do
    query = from(r in Entity) |> limit([], 3) |> select([], 0)
    assert SQL.select(query) == "SELECT 0\nFROM entity\nLIMIT 3"

    query = from(r in Entity) |> offset([], 5) |> select([], 0)
    assert SQL.select(query) == "SELECT 0\nFROM entity\nOFFSET 5"

    query = from(r in Entity) |> offset([], 5) |> limit([], 3) |> select([], 0)
    assert SQL.select(query) == "SELECT 0\nFROM entity\nLIMIT 3\nOFFSET 5"
  end

  test "variable binding" do
    x = 123
    query = from(r in Entity) |> select([], x)
    assert SQL.select(query) == "SELECT 123\nFROM entity"

    query = from(r in Entity) |> select([r], x + r.y)
    assert SQL.select(query) == "SELECT 123 + entity.y\nFROM entity"
  end

  test "string escape" do
    x = "'\\ \n"
    query = from(r in Entity) |> select([], x)
    assert SQL.select(query) == "SELECT '''\\\\ \n'\nFROM entity"

    query = from(r in Entity) |> select([], "'\\")
    assert SQL.select(query) == "SELECT '''\\\\'\nFROM entity"
  end

  test "unary ops" do
    query = from(r in Entity) |> select([r], +r.x)
    assert SQL.select(query) == "SELECT +entity.x\nFROM entity"

    query = from(r in Entity) |> select([r], -r.x)
    assert SQL.select(query) == "SELECT -entity.x\nFROM entity"
  end

  test "binary ops" do
    query = from(r in Entity) |> select([], 1 == 2)
    assert SQL.select(query) == "SELECT 1 = 2\nFROM entity"

    query = from(r in Entity) |> select([], 1 != 2)
    assert SQL.select(query) == "SELECT 1 != 2\nFROM entity"

    query = from(r in Entity) |> select([], 1 <= 2)
    assert SQL.select(query) == "SELECT 1 <= 2\nFROM entity"

    query = from(r in Entity) |> select([], 1 >= 2)
    assert SQL.select(query) == "SELECT 1 >= 2\nFROM entity"

    query = from(r in Entity) |> select([], 1 < 2)
    assert SQL.select(query) == "SELECT 1 < 2\nFROM entity"

    query = from(r in Entity) |> select([], 1 > 2)
    assert SQL.select(query) == "SELECT 1 > 2\nFROM entity"

    query = from(r in Entity) |> select([], 1 + 2)
    assert SQL.select(query) == "SELECT 1 + 2\nFROM entity"

    query = from(r in Entity) |> select([], 1 - 2)
    assert SQL.select(query) == "SELECT 1 - 2\nFROM entity"

    query = from(r in Entity) |> select([], 1 * 2)
    assert SQL.select(query) == "SELECT 1 * 2\nFROM entity"

    query = from(r in Entity) |> select([], 1 / 2)
    assert SQL.select(query) == "SELECT 1 / 2\nFROM entity"

    query = from(r in Entity) |> select([], true and false)
    assert SQL.select(query) == "SELECT TRUE AND FALSE\nFROM entity"

    query = from(r in Entity) |> select([], true or false)
    assert SQL.select(query) == "SELECT TRUE OR FALSE\nFROM entity"
  end

  test "binary op null check" do
    query = from(r in Entity) |> select([r], r.x == nil)
    assert SQL.select(query) == "SELECT entity.x IS NULL\nFROM entity"

    query = from(r in Entity) |> select([r], nil == r.x)
    assert SQL.select(query) == "SELECT entity.x IS NULL\nFROM entity"

    query = from(r in Entity) |> select([r], r.x != nil)
    assert SQL.select(query) == "SELECT entity.x IS NOT NULL\nFROM entity"

    query = from(r in Entity) |> select([r], nil != r.x)
    assert SQL.select(query) == "SELECT entity.x IS NOT NULL\nFROM entity"
  end

  test "literals" do
    query = from(r in Entity) |> select([], nil)
    assert SQL.select(query) == "SELECT NULL\nFROM entity"

    query = from(r in Entity) |> select([], true)
    assert SQL.select(query) == "SELECT TRUE\nFROM entity"

    query = from(r in Entity) |> select([], false)
    assert SQL.select(query) == "SELECT FALSE\nFROM entity"

    query = from(r in Entity) |> select([], "abc")
    assert SQL.select(query) == "SELECT 'abc'\nFROM entity"

    # TODO: Test more numbers
    query = from(r in Entity) |> select([], 123)
    assert SQL.select(query) == "SELECT 123\nFROM entity"
  end

  test "nested expressions" do
    z = 123
    query = from(r in Entity) |> select([r], r.x + (r.y + -z) - 3)
    assert SQL.select(query) == "SELECT (entity.x + (entity.y + -123)) - 3\nFROM entity"
  end

  test "use correct bindings" do
    query = from(r in Entity) |> select([not_r], not_r.x)
    assert SQL.select(query) == "SELECT entity.x\nFROM entity"
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
    assert SQL.select(query) == "SELECT 0\nFROM weird_name_123"
  end
end
