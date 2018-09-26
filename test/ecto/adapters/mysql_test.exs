Code.require_file "../../../integration_test/support/types.exs", __DIR__

defmodule Ecto.Adapters.MySQLTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Ecto.Queryable
  alias Ecto.Adapters.MySQL.Connection, as: SQL
  alias Ecto.Migration.Reference

  defmodule Schema do
    use Ecto.Schema

    schema "schema" do
      field :x, :integer
      field :y, :integer
      field :z, :integer

      has_many :comments, Ecto.Adapters.MySQLTest.Schema2,
        references: :x,
        foreign_key: :z
      has_one :permalink, Ecto.Adapters.MySQLTest.Schema3,
        references: :y,
        foreign_key: :id
    end
  end

  defmodule Schema2 do
    use Ecto.Schema

    schema "schema2" do
      belongs_to :post, Ecto.Adapters.MySQLTest.Schema,
        references: :x,
        foreign_key: :z
    end
  end

  defmodule Schema3 do
    use Ecto.Schema

    schema "schema3" do
      field :binary, :binary
    end
  end

  defp plan(query, operation \\ :all) do
    {query, _params} = Ecto.Adapter.Queryable.plan_query(operation, Ecto.Adapters.MySQL, query)
    query
  end

  defp all(query), do: query |> SQL.all |> IO.iodata_to_binary()
  defp update_all(query), do: query |> SQL.update_all |> IO.iodata_to_binary()
  defp delete_all(query), do: query |> SQL.delete_all |> IO.iodata_to_binary()
  defp execute_ddl(query), do: query |> SQL.execute_ddl |> Enum.map(&IO.iodata_to_binary/1)

  defp insert(prefx, table, header, rows, on_conflict, returning) do
    IO.iodata_to_binary SQL.insert(prefx, table, header, rows, on_conflict, returning)
  end

  defp update(prefx, table, fields, filter, returning) do
    IO.iodata_to_binary SQL.update(prefx, table, fields, filter, returning)
  end

  defp delete(prefx, table, filter, returning) do
    IO.iodata_to_binary SQL.delete(prefx, table, filter, returning)
  end

  test "from" do
    query = Schema |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0}
  end

  test "from with hints" do
    query = Schema |> from(hints: ["USE INDEX FOO", "USE INDEX BAR"]) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0 USE INDEX FOO USE INDEX BAR}
  end

  test "from without schema" do
    query = "posts" |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT p0.`x` FROM `posts` AS p0}

    query = "Posts" |> select([:x]) |> plan()
    assert all(query) == ~s{SELECT P0.`x` FROM `Posts` AS P0}

    query = "0posts" |> select([:x]) |> plan()
    assert all(query) == ~s{SELECT t0.`x` FROM `0posts` AS t0}
  end

  test "from with subquery" do
    query = subquery("posts" |> select([r], %{x: r.x, y: r.y})) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.`x` FROM (SELECT p0.`x` AS `x`, p0.`y` AS `y` FROM `posts` AS p0) AS s0}

    query = subquery("posts" |> select([r], %{x: r.x, z: r.y})) |> select([r], r) |> plan()
    assert all(query) == ~s{SELECT s0.`x`, s0.`z` FROM (SELECT p0.`x` AS `x`, p0.`y` AS `z` FROM `posts` AS p0) AS s0}
  end

  test "select" do
    query = Schema |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT s0.`x`, s0.`y` FROM `schema` AS s0}

    query = Schema |> select([r], [r.x, r.y]) |> plan()
    assert all(query) == ~s{SELECT s0.`x`, s0.`y` FROM `schema` AS s0}

    query = Schema |> select([r], struct(r, [:x, :y])) |> plan()
    assert all(query) == ~s{SELECT s0.`x`, s0.`y` FROM `schema` AS s0}
  end

  test "distinct" do
    query = Schema |> distinct([r], true) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT DISTINCT s0.`x`, s0.`y` FROM `schema` AS s0}

    query = Schema |> distinct([r], false) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT s0.`x`, s0.`y` FROM `schema` AS s0}

    query = Schema |> distinct(true) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT DISTINCT s0.`x`, s0.`y` FROM `schema` AS s0}

    query = Schema |> distinct(false) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT s0.`x`, s0.`y` FROM `schema` AS s0}

    assert_raise Ecto.QueryError, ~r"DISTINCT with multiple columns is not supported by MySQL", fn ->
      query = Schema |> distinct([r], [r.x, r.y]) |> select([r], {r.x, r.y}) |> plan()
      all(query)
    end
  end

  test "where" do
    query = Schema |> where([r], r.x == 42) |> where([r], r.y != 43) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0 WHERE (s0.`x` = 42) AND (s0.`y` != 43)}

    query = Schema |> where([r], {r.x, r.y} > {1, 2}) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0 WHERE ((s0.`x`,s0.`y`) > (1,2))}
  end

  test "or_where" do
    query = Schema |> or_where([r], r.x == 42) |> or_where([r], r.y != 43) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0 WHERE (s0.`x` = 42) OR (s0.`y` != 43)}

    query = Schema |> or_where([r], r.x == 42) |> or_where([r], r.y != 43) |> where([r], r.z == 44) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0 WHERE ((s0.`x` = 42) OR (s0.`y` != 43)) AND (s0.`z` = 44)}
  end

  test "order by" do
    query = Schema |> order_by([r], r.x) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0 ORDER BY s0.`x`}

    query = Schema |> order_by([r], [r.x, r.y]) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0 ORDER BY s0.`x`, s0.`y`}

    query = Schema |> order_by([r], [asc: r.x, desc: r.y]) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0 ORDER BY s0.`x`, s0.`y` DESC}

    query = Schema |> order_by([r], []) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0}

    for dir <- [:asc_nulls_first, :asc_nulls_last, :desc_nulls_first, :desc_nulls_last] do
      assert_raise Ecto.QueryError, ~r"#{dir} is not supported in ORDER BY in MySQL", fn ->
        Schema |> order_by([r], [{^dir, r.x}]) |> select([r], r.x) |> plan() |> all()
      end
    end
  end

  test "union and union all" do
    base_query = Schema |> select([r], r.x) |> order_by([r], r.x) |> offset(10) |> limit(5)
    union_query1 = Schema |> select([r], r.y) |> order_by([r], r.y) |> offset(20) |> limit(40)
    union_query2 = Schema |> select([r], r.z) |> order_by([r], r.z) |> offset(30) |> limit(60)

    query = base_query |> union(union_query1) |> union(union_query2) |> plan()

    assert all(query) ==
             ~s{SELECT s0.`x` FROM `schema` AS s0 } <>
               ~s{UNION (SELECT s0.`y` FROM `schema` AS s0 ORDER BY s0.`y` LIMIT 40 OFFSET 20) } <>
               ~s{UNION (SELECT s0.`z` FROM `schema` AS s0 ORDER BY s0.`z` LIMIT 60 OFFSET 30) } <>
               ~s{ORDER BY s0.`x` LIMIT 5 OFFSET 10}

    query = base_query |> union_all(union_query1) |> union_all(union_query2) |> plan()

    assert all(query) ==
             ~s{SELECT s0.`x` FROM `schema` AS s0 } <>
               ~s{UNION ALL (SELECT s0.`y` FROM `schema` AS s0 ORDER BY s0.`y` LIMIT 40 OFFSET 20) } <>
               ~s{UNION ALL (SELECT s0.`z` FROM `schema` AS s0 ORDER BY s0.`z` LIMIT 60 OFFSET 30) } <>
               ~s{ORDER BY s0.`x` LIMIT 5 OFFSET 10}
  end

  test "except and except all" do
    base_query = Schema |> select([r], r.x) |> order_by([r], r.x) |> offset(10) |> limit(5)
    except_query1 = Schema |> select([r], r.y) |> order_by([r], r.y) |> offset(20) |> limit(40)
    except_query2 = Schema |> select([r], r.z) |> order_by([r], r.z) |> offset(30) |> limit(60)

    query = base_query |> except(except_query1) |> except(except_query2) |> plan()

    assert all(query) ==
             ~s{SELECT s0.`x` FROM `schema` AS s0 } <>
               ~s{EXCEPT (SELECT s0.`y` FROM `schema` AS s0 ORDER BY s0.`y` LIMIT 40 OFFSET 20) } <>
               ~s{EXCEPT (SELECT s0.`z` FROM `schema` AS s0 ORDER BY s0.`z` LIMIT 60 OFFSET 30) } <>
               ~s{ORDER BY s0.`x` LIMIT 5 OFFSET 10}

    query = base_query |> except_all(except_query1) |> except_all(except_query2) |> plan()

    assert all(query) ==
             ~s{SELECT s0.`x` FROM `schema` AS s0 } <>
               ~s{EXCEPT ALL (SELECT s0.`y` FROM `schema` AS s0 ORDER BY s0.`y` LIMIT 40 OFFSET 20) } <>
               ~s{EXCEPT ALL (SELECT s0.`z` FROM `schema` AS s0 ORDER BY s0.`z` LIMIT 60 OFFSET 30) } <>
               ~s{ORDER BY s0.`x` LIMIT 5 OFFSET 10}
  end

  test "intersect and intersect all" do
    base_query = Schema |> select([r], r.x) |> order_by([r], r.x) |> offset(10) |> limit(5)
    intersect_query1 = Schema |> select([r], r.y) |> order_by([r], r.y) |> offset(20) |> limit(40)
    intersect_query2 = Schema |> select([r], r.z) |> order_by([r], r.z) |> offset(30) |> limit(60)

    query = base_query |> intersect(intersect_query1) |> intersect(intersect_query2) |> plan()

    assert all(query) ==
             ~s{SELECT s0.`x` FROM `schema` AS s0 } <>
               ~s{INTERSECT (SELECT s0.`y` FROM `schema` AS s0 ORDER BY s0.`y` LIMIT 40 OFFSET 20) } <>
               ~s{INTERSECT (SELECT s0.`z` FROM `schema` AS s0 ORDER BY s0.`z` LIMIT 60 OFFSET 30) } <>
               ~s{ORDER BY s0.`x` LIMIT 5 OFFSET 10}

    query =
      base_query |> intersect_all(intersect_query1) |> intersect_all(intersect_query2) |> plan()

    assert all(query) ==
             ~s{SELECT s0.`x` FROM `schema` AS s0 } <>
               ~s{INTERSECT ALL (SELECT s0.`y` FROM `schema` AS s0 ORDER BY s0.`y` LIMIT 40 OFFSET 20) } <>
               ~s{INTERSECT ALL (SELECT s0.`z` FROM `schema` AS s0 ORDER BY s0.`z` LIMIT 60 OFFSET 30) } <>
               ~s{ORDER BY s0.`x` LIMIT 5 OFFSET 10}
  end

  test "limit and offset" do
    query = Schema |> limit([r], 3) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM `schema` AS s0 LIMIT 3}

    query = Schema |> offset([r], 5) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM `schema` AS s0 OFFSET 5}

    query = Schema |> offset([r], 5) |> limit([r], 3) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM `schema` AS s0 LIMIT 3 OFFSET 5}
  end

  test "aggregates" do
    query = Schema |> select(count()) |> plan()
    assert all(query) == ~s{SELECT count(*) FROM `schema` AS s0}
  end

  test "aggregate filters" do
    query = Schema |> select([r], count(r.x) |> filter(r.x > 10)) |> plan()
    assert_raise Ecto.QueryError, ~r/MySQL adapter does not support aggregate filters in query/, fn ->
      all(query)
    end
  end

  test "lock" do
    query = Schema |> lock("LOCK IN SHARE MODE") |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM `schema` AS s0 LOCK IN SHARE MODE}
  end

  test "coalesce" do
    query = Schema |> select([s], coalesce(s.x, 5)) |> plan()
    assert all(query) == ~s{SELECT coalesce(s0.`x`, 5) FROM `schema` AS s0}
  end

  test "string escape" do
    query = "schema" |> where(foo: "'\\  ") |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM `schema` AS s0 WHERE (s0.`foo` = '''\\\\  ')}

    query = "schema" |> where(foo: "'") |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM `schema` AS s0 WHERE (s0.`foo` = '''')}
  end

  test "binary ops" do
    query = Schema |> select([r], r.x == 2) |> plan()
    assert all(query) == ~s{SELECT s0.`x` = 2 FROM `schema` AS s0}

    query = Schema |> select([r], r.x != 2) |> plan()
    assert all(query) == ~s{SELECT s0.`x` != 2 FROM `schema` AS s0}

    query = Schema |> select([r], r.x <= 2) |> plan()
    assert all(query) == ~s{SELECT s0.`x` <= 2 FROM `schema` AS s0}

    query = Schema |> select([r], r.x >= 2) |> plan()
    assert all(query) == ~s{SELECT s0.`x` >= 2 FROM `schema` AS s0}

    query = Schema |> select([r], r.x < 2) |> plan()
    assert all(query) == ~s{SELECT s0.`x` < 2 FROM `schema` AS s0}

    query = Schema |> select([r], r.x > 2) |> plan()
    assert all(query) == ~s{SELECT s0.`x` > 2 FROM `schema` AS s0}

    query = Schema |> select([r], r.x + 2) |> plan()
    assert all(query) == ~s{SELECT s0.`x` + 2 FROM `schema` AS s0}
  end

  test "is_nil" do
    query = Schema |> select([r], is_nil(r.x)) |> plan()
    assert all(query) == ~s{SELECT s0.`x` IS NULL FROM `schema` AS s0}

    query = Schema |> select([r], not is_nil(r.x)) |> plan()
    assert all(query) == ~s{SELECT NOT (s0.`x` IS NULL) FROM `schema` AS s0}
  end

  test "order_by and types" do
    query = "schema3" |> order_by([e], type(fragment("?", e.binary), ^:decimal)) |> select(true) |> plan()
    assert all(query) == "SELECT TRUE FROM `schema3` AS s0 ORDER BY s0.`binary` + 0"
  end

  test "fragments" do
    query = Schema |> select([r], fragment("now")) |> plan()
    assert all(query) == ~s{SELECT now FROM `schema` AS s0}

    query = Schema |> select([r], fragment("fun(?)", r)) |> plan()
    assert all(query) == ~s{SELECT fun(s0) FROM `schema` AS s0}

    query = Schema |> select([r], fragment("lcase(?)", r.x)) |> plan()
    assert all(query) == ~s{SELECT lcase(s0.`x`) FROM `schema` AS s0}

    query = Schema |> select([r], r.x) |> where([], fragment("? = \"query\\?\"", ^10)) |> plan()
    assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0 WHERE (? = \"query?\")}

    value = 13
    query = Schema |> select([r], fragment("lcase(?, ?)", r.x, ^value)) |> plan()
    assert all(query) == ~s{SELECT lcase(s0.`x`, ?) FROM `schema` AS s0}

    query = Schema |> select([], fragment(title: 2)) |> plan()
    assert_raise Ecto.QueryError, fn ->
      all(query)
    end
  end

  test "literals" do
    query = "schema" |> where(foo: true) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM `schema` AS s0 WHERE (s0.`foo` = TRUE)}

    query = "schema" |> where(foo: false) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM `schema` AS s0 WHERE (s0.`foo` = FALSE)}

    query = "schema" |> where(foo: "abc") |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM `schema` AS s0 WHERE (s0.`foo` = 'abc')}

    query = "schema" |> where(foo: 123) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM `schema` AS s0 WHERE (s0.`foo` = 123)}

    query = "schema" |> where(foo: 123.0) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM `schema` AS s0 WHERE (s0.`foo` = (0 + 123.0))}
  end

  test "tagged type" do
    query = Schema |> select([], type(^"601d74e4-a8d3-4b6e-8365-eddb4c893327", Ecto.UUID)) |> plan()
    assert all(query) == ~s{SELECT CAST(? AS binary(16)) FROM `schema` AS s0}
  end

  test "string type" do
    query = Schema |> select([], type(^"test", :string)) |> plan()
    assert all(query) == ~s{SELECT CAST(? AS char) FROM `schema` AS s0}
  end

  test "nested expressions" do
    z = 123
    query = from(r in Schema, []) |> select([r], r.x > 0 and (r.y > ^(-z)) or true) |> plan()
    assert all(query) == ~s{SELECT ((s0.`x` > 0) AND (s0.`y` > ?)) OR TRUE FROM `schema` AS s0}
  end

  test "in expression" do
    query = Schema |> select([e], 1 in []) |> plan()
    assert all(query) == ~s{SELECT false FROM `schema` AS s0}

    query = Schema |> select([e], 1 in [1,e.x,3]) |> plan()
    assert all(query) == ~s{SELECT 1 IN (1,s0.`x`,3) FROM `schema` AS s0}

    query = Schema |> select([e], 1 in ^[]) |> plan()
    assert all(query) == ~s{SELECT false FROM `schema` AS s0}

    query = Schema |> select([e], 1 in ^[1, 2, 3]) |> plan()
    assert all(query) == ~s{SELECT 1 IN (?,?,?) FROM `schema` AS s0}

    query = Schema |> select([e], 1 in [1, ^2, 3]) |> plan()
    assert all(query) == ~s{SELECT 1 IN (1,?,3) FROM `schema` AS s0}

    query = Schema |> select([e], 1 in fragment("foo")) |> plan()
    assert all(query) == ~s{SELECT 1 = ANY(foo) FROM `schema` AS s0}

    query = Schema |> select([e], e.x == ^0 or e.x in ^[1, 2, 3] or e.x == ^4) |> plan()
    assert all(query) == ~s{SELECT ((s0.`x` = ?) OR s0.`x` IN (?,?,?)) OR (s0.`x` = ?) FROM `schema` AS s0}
  end

  test "having" do
    query = Schema |> having([p], p.x == p.x) |> select([p], p.x) |> plan()
    assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0 HAVING (s0.`x` = s0.`x`)}

    query = Schema |> having([p], p.x == p.x) |> having([p], p.y == p.y) |> select([p], [p.y, p.x]) |> plan()
    assert all(query) == ~s{SELECT s0.`y`, s0.`x` FROM `schema` AS s0 HAVING (s0.`x` = s0.`x`) AND (s0.`y` = s0.`y`)}
  end

  test "or_having" do
    query = Schema |> or_having([p], p.x == p.x) |> select([p], p.x) |> plan()
    assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0 HAVING (s0.`x` = s0.`x`)}

    query = Schema |> or_having([p], p.x == p.x) |> or_having([p], p.y == p.y) |> select([p], [p.y, p.x]) |> plan()
    assert all(query) == ~s{SELECT s0.`y`, s0.`x` FROM `schema` AS s0 HAVING (s0.`x` = s0.`x`) OR (s0.`y` = s0.`y`)}
  end

  test "group by" do
    query = Schema |> group_by([r], r.x) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0 GROUP BY s0.`x`}

    query = Schema |> group_by([r], 2) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0 GROUP BY 2}

    query = Schema |> group_by([r], [r.x, r.y]) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0 GROUP BY s0.`x`, s0.`y`}

    query = Schema |> group_by([r], []) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0}
  end

  test "interpolated values" do
    query = Schema
            |> select([m], {m.id, ^0})
            |> join(:inner, [], Schema2, on: fragment("?", ^true))
            |> join(:inner, [], Schema2, on: fragment("?", ^false))
            |> where([], fragment("?", ^true))
            |> where([], fragment("?", ^false))
            |> having([], fragment("?", ^true))
            |> having([], fragment("?", ^false))
            |> group_by([], fragment("?", ^1))
            |> group_by([], fragment("?", ^2))
            |> union("schema1" |> select([m], {m.id, ^true}) |> where([], fragment("?", ^3)))
            |> union_all("schema2" |> select([m], {m.id, ^false}) |> where([], fragment("?", ^4)))
            |> order_by([], fragment("?", ^5))
            |> order_by([], ^:x)
            |> limit([], ^6)
            |> offset([], ^7)
            |> plan()

    result =
      "SELECT s0.`id`, ? FROM `schema` AS s0 INNER JOIN `schema2` AS s1 ON ? " <>
      "INNER JOIN `schema2` AS s2 ON ? WHERE (?) AND (?) " <>
      "GROUP BY ?, ? HAVING (?) AND (?) " <>
      "UNION (SELECT s0.`id`, ? FROM `schema1` AS s0 WHERE (?)) " <>
      "UNION ALL (SELECT s0.`id`, ? FROM `schema2` AS s0 WHERE (?)) " <>
      "ORDER BY ?, s0.`x` LIMIT ? OFFSET ?"

    assert all(query) == String.trim(result)
  end

  ## *_all

  test "update all" do
    query = from(m in Schema, update: [set: [x: 0]]) |> plan(:update_all)
    assert update_all(query) ==
           ~s{UPDATE `schema` AS s0 SET s0.`x` = 0}

    query = from(m in Schema, update: [set: [x: 0], inc: [y: 1, z: -3]]) |> plan(:update_all)
    assert update_all(query) ==
           ~s{UPDATE `schema` AS s0 SET s0.`x` = 0, s0.`y` = s0.`y` + 1, s0.`z` = s0.`z` + -3}

    query = from(e in Schema, where: e.x == 123, update: [set: [x: 0]]) |> plan(:update_all)
    assert update_all(query) ==
           ~s{UPDATE `schema` AS s0 SET s0.`x` = 0 WHERE (s0.`x` = 123)}

    query = from(m in Schema, update: [set: [x: ^0]]) |> plan(:update_all)
    assert update_all(query) ==
           ~s{UPDATE `schema` AS s0 SET s0.`x` = ?}

    query = Schema |> join(:inner, [p], q in Schema2, on: p.x == q.z)
                  |> update([_], set: [x: 0]) |> plan(:update_all)
    assert update_all(query) ==
           ~s{UPDATE `schema` AS s0, `schema2` AS s1 SET s0.`x` = 0 WHERE (s0.`x` = s1.`z`)}

    query = from(e in Schema, where: e.x == 123, update: [set: [x: 0]],
                             join: q in Schema2, on: e.x == q.z) |> plan(:update_all)
    assert update_all(query) ==
           ~s{UPDATE `schema` AS s0, `schema2` AS s1 } <>
           ~s{SET s0.`x` = 0 WHERE (s0.`x` = s1.`z`) AND (s0.`x` = 123)}
  end

  test "update all with prefix" do
    query = from(m in Schema, update: [set: [x: 0]]) |> Map.put(:prefix, "prefix") |> plan(:update_all)
    assert update_all(query) == ~s{UPDATE `prefix`.`schema` AS s0 SET s0.`x` = 0}

    query = from(m in Schema, prefix: "first", update: [set: [x: 0]]) |> Map.put(:prefix, "prefix") |> plan(:update_all)
    assert update_all(query) == ~s{UPDATE `first`.`schema` AS s0 SET s0.`x` = 0}
  end

  test "delete all" do
    query = Schema |> Queryable.to_query |> plan()
    assert delete_all(query) == ~s{DELETE s0.* FROM `schema` AS s0}

    query = from(e in Schema, where: e.x == 123) |> plan()
    assert delete_all(query) ==
           ~s{DELETE s0.* FROM `schema` AS s0 WHERE (s0.`x` = 123)}

    query = Schema |> join(:inner, [p], q in Schema2, on: p.x == q.z) |> plan()
    assert delete_all(query) ==
           ~s{DELETE s0.* FROM `schema` AS s0 INNER JOIN `schema2` AS s1 ON s0.`x` = s1.`z`}

    query = from(e in Schema, where: e.x == 123, join: q in Schema2, on: e.x == q.z) |> plan()
    assert delete_all(query) ==
           ~s{DELETE s0.* FROM `schema` AS s0 } <>
           ~s{INNER JOIN `schema2` AS s1 ON s0.`x` = s1.`z` WHERE (s0.`x` = 123)}
  end

  test "delete all with prefix" do
    query = Schema |> Queryable.to_query |> Map.put(:prefix, "prefix") |> plan()
    assert delete_all(query) == ~s{DELETE s0.* FROM `prefix`.`schema` AS s0}

    query = Schema |> from(prefix: "first") |> Map.put(:prefix, "prefix") |> plan()
    assert delete_all(query) == ~s{DELETE s0.* FROM `first`.`schema` AS s0}
  end

  ## Partitions and windows

  describe "windows" do
    test "one window" do
      query = Schema
              |> select([r], r.x)
              |> windows([r], w: [partition_by: r.x])
              |> plan

      assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0 WINDOW `w` AS (PARTITION BY s0.`x`)}
    end

    test "two windows" do
      query = Schema
              |> select([r], r.x)
              |> windows([r], w1: [partition_by: r.x], w2: [partition_by: r.y])
              |> plan()
      assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0 WINDOW `w1` AS (PARTITION BY s0.`x`), `w2` AS (PARTITION BY s0.`y`)}
    end

    test "count over window" do
      query = Schema
              |> windows([r], w: [partition_by: r.x])
              |> select([r], count(r.x) |> over(:w))
              |> plan()
      assert all(query) == ~s{SELECT count(s0.`x`) OVER `w` FROM `schema` AS s0 WINDOW `w` AS (PARTITION BY s0.`x`)}
    end

    test "count over all" do
      query = Schema
              |> select([r], count(r.x) |> over)
              |> plan()
      assert all(query) == ~s{SELECT count(s0.`x`) OVER () FROM `schema` AS s0}
    end

    test "row_number over all" do
      query = Schema
              |> select(row_number |> over)
              |> plan()
      assert all(query) == ~s{SELECT row_number() OVER () FROM `schema` AS s0}
    end

    test "nth_value over all" do
      query = Schema
              |> select([r], nth_value(r.x, 42) |> over)
              |> plan()
      assert all(query) == ~s{SELECT nth_value(s0.`x`, 42) OVER () FROM `schema` AS s0}
    end

    test "lag/2 over all" do
      query = Schema
              |> select([r], lag(r.x, 42) |> over)
              |> plan()
      assert all(query) == ~s{SELECT lag(s0.`x`, 42) OVER () FROM `schema` AS s0}
    end

    test "custom aggregation over all" do
      query = Schema
              |> select([r], fragment("custom_function(?)", r.x) |> over)
              |> plan()
      assert all(query) == ~s{SELECT custom_function(s0.`x`) OVER () FROM `schema` AS s0}
    end

    test "partition by and order by on window" do
      query = Schema
              |> windows([r], w: [partition_by: [r.x, r.z], order_by: r.x])
              |> select([r], r.x)
              |> plan()
      assert all(query) == ~s{SELECT s0.`x` FROM `schema` AS s0 WINDOW `w` AS (PARTITION BY s0.`x`, s0.`z` ORDER BY s0.`x`)}
    end

    test "partition by and order by on over" do
      query = Schema
              |> select([r], count(r.x) |> over(partition_by: [r.x, r.z], order_by: r.x))

      query = query |> plan()
      assert all(query) == ~s{SELECT count(s0.`x`) OVER (PARTITION BY s0.`x`, s0.`z` ORDER BY s0.`x`) FROM `schema` AS s0}
    end
  end

  ## Joins

  test "join" do
    query = Schema |> join(:inner, [p], q in Schema2, on: p.x == q.z) |> select([], true) |> plan()
    assert all(query) ==
           ~s{SELECT TRUE FROM `schema` AS s0 INNER JOIN `schema2` AS s1 ON s0.`x` = s1.`z`}

    query = Schema |> join(:inner, [p], q in Schema2, on: p.x == q.z)
                  |> join(:inner, [], Schema, on: true) |> select([], true) |> plan()
    assert all(query) ==
           ~s{SELECT TRUE FROM `schema` AS s0 INNER JOIN `schema2` AS s1 ON s0.`x` = s1.`z` } <>
           ~s{INNER JOIN `schema` AS s2 ON TRUE}
  end

  test "join with hints" do
    assert Schema
           |> join(:inner, [p], q in Schema2, hints: ["USE INDEX FOO", "USE INDEX BAR"])
           |> select([], true)
           |> plan()
           |> all() == ~s{SELECT TRUE FROM `schema` AS s0 INNER JOIN `schema2` AS s1 USE INDEX FOO USE INDEX BAR ON TRUE}
  end

  test "join with nothing bound" do
    query = Schema |> join(:inner, [], q in Schema2, on: q.z == q.z) |> select([], true) |> plan()
    assert all(query) ==
           ~s{SELECT TRUE FROM `schema` AS s0 INNER JOIN `schema2` AS s1 ON s1.`z` = s1.`z`}
  end

  test "join without schema" do
    query = "posts" |> join(:inner, [p], q in "comments", on: p.x == q.z) |> select([], true) |> plan()
    assert all(query) ==
           ~s{SELECT TRUE FROM `posts` AS p0 INNER JOIN `comments` AS c1 ON p0.`x` = c1.`z`}
  end

  test "join with subquery" do
    posts = subquery("posts" |> where(title: ^"hello") |> select([r], %{x: r.x, y: r.y}))
    query = "comments" |> join(:inner, [c], p in subquery(posts), on: true) |> select([_, p], p.x) |> plan()
    assert all(query) ==
           ~s{SELECT s1.`x` FROM `comments` AS c0 } <>
           ~s{INNER JOIN (SELECT p0.`x` AS `x`, p0.`y` AS `y` FROM `posts` AS p0 WHERE (p0.`title` = ?)) AS s1 ON TRUE}

    posts = subquery("posts" |> where(title: ^"hello") |> select([r], %{x: r.x, z: r.y}))
    query = "comments" |> join(:inner, [c], p in subquery(posts), on: true) |> select([_, p], p) |> plan()
    assert all(query) ==
           ~s{SELECT s1.`x`, s1.`z` FROM `comments` AS c0 } <>
           ~s{INNER JOIN (SELECT p0.`x` AS `x`, p0.`y` AS `z` FROM `posts` AS p0 WHERE (p0.`title` = ?)) AS s1 ON TRUE}
  end

  test "join with prefix" do
    query = Schema |> join(:inner, [p], q in Schema2, on: p.x == q.z) |> select([], true) |> Map.put(:prefix, "prefix") |> plan()
    assert all(query) ==
           ~s{SELECT TRUE FROM `prefix`.`schema` AS s0 INNER JOIN `prefix`.`schema2` AS s1 ON s0.`x` = s1.`z`}

    query = Schema |> from(prefix: "first") |> join(:inner, [p], q in Schema2, on: p.x == q.z, prefix: "second") |> select([], true) |> Map.put(:prefix, "prefix") |> plan()
    assert all(query) ==
           ~s{SELECT TRUE FROM `first`.`schema` AS s0 INNER JOIN `second`.`schema2` AS s1 ON s0.`x` = s1.`z`}
  end

  test "join with fragment" do
    query = Schema
            |> join(:inner, [p], q in fragment("SELECT * FROM schema2 AS s2 WHERE s2.id = ? AND s2.field = ?", p.x, ^10))
            |> select([p], {p.id, ^0})
            |> where([p], p.id > 0 and p.id < ^100)
            |> plan()
    assert all(query) ==
           ~s{SELECT s0.`id`, ? FROM `schema` AS s0 INNER JOIN } <>
           ~s{(SELECT * FROM schema2 AS s2 WHERE s2.id = s0.`x` AND s2.field = ?) AS f1 ON TRUE } <>
           ~s{WHERE ((s0.`id` > 0) AND (s0.`id` < ?))}
  end

  test "join with fragment and on defined" do
    query = Schema
            |> join(:inner, [p], q in fragment("SELECT * FROM schema2"), on: q.id == p.id)
            |> select([p], {p.id, ^0})
            |> plan()
    assert all(query) ==
           ~s{SELECT s0.`id`, ? FROM `schema` AS s0 INNER JOIN } <>
           ~s{(SELECT * FROM schema2) AS f1 ON f1.`id` = s0.`id`}
  end

  test "join with query interpolation" do
    inner = Ecto.Queryable.to_query(Schema2)
    query = from(p in Schema, left_join: c in ^inner, select: {p.id, c.id}) |> plan()
    assert all(query) ==
           "SELECT s0.`id`, s1.`id` FROM `schema` AS s0 LEFT OUTER JOIN `schema2` AS s1 ON TRUE"
  end

  test "cross join" do
    query = from(p in Schema, cross_join: c in Schema2, select: {p.id, c.id}) |> plan()
    assert all(query) ==
           "SELECT s0.`id`, s1.`id` FROM `schema` AS s0 CROSS JOIN `schema2` AS s1"
  end

  test "join produces correct bindings" do
    query = from(p in Schema, join: c in Schema2, on: true)
    query = from(p in query, join: c in Schema2, on: true, select: {p.id, c.id})
    query = plan(query)
    assert all(query) ==
           "SELECT s0.`id`, s2.`id` FROM `schema` AS s0 INNER JOIN `schema2` AS s1 ON TRUE INNER JOIN `schema2` AS s2 ON TRUE"
  end

  ## Associations

  test "association join belongs_to" do
    query = Schema2 |> join(:inner, [c], p in assoc(c, :post)) |> select([], true) |> plan()
    assert all(query) ==
           "SELECT TRUE FROM `schema2` AS s0 INNER JOIN `schema` AS s1 ON s1.`x` = s0.`z`"
  end

  test "association join has_many" do
    query = Schema |> join(:inner, [p], c in assoc(p, :comments)) |> select([], true) |> plan()
    assert all(query) ==
           "SELECT TRUE FROM `schema` AS s0 INNER JOIN `schema2` AS s1 ON s1.`z` = s0.`x`"
  end

  test "association join has_one" do
    query = Schema |> join(:inner, [p], pp in assoc(p, :permalink)) |> select([], true) |> plan()
    assert all(query) ==
           "SELECT TRUE FROM `schema` AS s0 INNER JOIN `schema3` AS s1 ON s1.`id` = s0.`y`"
  end

  # Schema based

  test "insert" do
    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {:raise, [], []}, [])
    assert query == ~s{INSERT INTO `schema` (`x`,`y`) VALUES (?,?)}

    query = insert(nil, "schema", [:x, :y], [[:x, :y], [nil, :y]], {:raise, [], []}, [])
    assert query == ~s{INSERT INTO `schema` (`x`,`y`) VALUES (?,?),(DEFAULT,?)}

    query = insert(nil, "schema", [], [[]], {:raise, [], []}, [])
    assert query == ~s{INSERT INTO `schema` () VALUES ()}

    query = insert("prefix", "schema", [], [[]], {:raise, [], []}, [])
    assert query == ~s{INSERT INTO `prefix`.`schema` () VALUES ()}
  end

  test "insert with on duplicate key" do
    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {:nothing, [], []}, [])
    assert query == ~s{INSERT INTO `schema` (`x`,`y`) VALUES (?,?) ON DUPLICATE KEY UPDATE `x` = `x`}

    update = from("schema", update: [set: [z: "foo"]]) |> plan(:update_all)
    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {update, [], []}, [])
    assert query == ~s{INSERT INTO `schema` (`x`,`y`) VALUES (?,?) ON DUPLICATE KEY UPDATE `z` = 'foo'}

    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {[:x, :y], [], []}, [])
    assert query == ~s{INSERT INTO `schema` (`x`,`y`) VALUES (?,?) ON DUPLICATE KEY UPDATE `x` = VALUES(`x`),`y` = VALUES(`y`)}

    assert_raise ArgumentError, "The :conflict_target option is not supported in insert/insert_all by MySQL", fn ->
      insert(nil, "schema", [:x, :y], [[:x, :y]], {[:x, :y], [], [:x]}, [])
    end

    assert_raise ArgumentError, "Using a query with :where in combination with the :on_conflict option is not supported by MySQL", fn ->
      update = from("schema", update: [set: [x: ^"foo"]], where: [z: "bar"]) |> plan(:update_all)
      insert(nil, "schema", [:x, :y], [[:x, :y]], {update, [], []}, [])
    end
  end

  test "update" do
    query = update(nil, "schema", [:id], [x: 1, y: 2], [])
    assert query == ~s{UPDATE `schema` SET `id` = ? WHERE `x` = ? AND `y` = ?}

    query = update("prefix", "schema", [:id], [x: 1, y: 2], [])
    assert query == ~s{UPDATE `prefix`.`schema` SET `id` = ? WHERE `x` = ? AND `y` = ?}

    query = update("prefix", "schema", [:id], [x: 1, y: nil], [])
    assert query == ~s{UPDATE `prefix`.`schema` SET `id` = ? WHERE `x` = ? AND `y` IS NULL}
  end

  test "delete" do
    query = delete(nil, "schema", [x: 1, y: 2], [])
    assert query == ~s{DELETE FROM `schema` WHERE `x` = ? AND `y` = ?}

    query = delete("prefix", "schema", [x: 1, y: 2], [])
    assert query == ~s{DELETE FROM `prefix`.`schema` WHERE `x` = ? AND `y` = ?}

    query = delete(nil, "schema", [x: nil, y: 1], [])
    assert query == ~s{DELETE FROM `schema` WHERE `x` IS NULL AND `y` = ?}
  end

  # DDL

  import Ecto.Migration, only: [table: 1, table: 2, index: 2, index: 3,
                                constraint: 3]

  test "executing a string during migration" do
    assert execute_ddl("example") == ["example"]
  end

  test "create table" do
    create = {:create, table(:posts),
               [{:add, :name, :string, [default: "Untitled", size: 20, null: false]},
                {:add, :price, :numeric, [precision: 8, scale: 2, default: {:fragment, "expr"}]},
                {:add, :on_hand, :integer, [default: 0, null: true]},
                {:add, :likes, :"smallint unsigned", [default: 0, null: false]},
                {:add, :published_at, :"datetime(6)", [null: true]},
                {:add, :is_active, :boolean, [default: true]}]}

    assert execute_ddl(create) == ["""
    CREATE TABLE `posts` (`name` varchar(20) DEFAULT 'Untitled' NOT NULL,
    `price` numeric(8,2) DEFAULT expr,
    `on_hand` integer DEFAULT 0 NULL,
    `likes` smallint unsigned DEFAULT 0 NOT NULL,
    `published_at` datetime(6) NULL,
    `is_active` boolean DEFAULT true) ENGINE = INNODB
    """ |> remove_newlines]
  end

  test "create empty table" do
    create = {:create, table(:posts), []}

    assert execute_ddl(create) == ["""
    CREATE TABLE `posts` ENGINE = INNODB
    """ |> remove_newlines]
  end

  test "create table with prefix" do
    create = {:create, table(:posts, prefix: :foo),
               [{:add, :category_0, %Reference{table: :categories}, []}]}

    assert execute_ddl(create) == ["""
    CREATE TABLE `foo`.`posts` (`category_0` BIGINT UNSIGNED,
    CONSTRAINT `posts_category_0_fkey` FOREIGN KEY (`category_0`) REFERENCES `foo`.`categories`(`id`)) ENGINE = INNODB
    """ |> remove_newlines]
  end

  test "create table with engine" do
    create = {:create, table(:posts, engine: :myisam),
               [{:add, :id, :serial, [primary_key: true]}]}
    assert execute_ddl(create) ==
           [~s|CREATE TABLE `posts` (`id` bigint unsigned not null auto_increment, PRIMARY KEY (`id`)) ENGINE = MYISAM|]
  end

  test "create table with references" do
    create = {:create, table(:posts),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :category_0, %Reference{table: :categories}, []},
                {:add, :category_1, %Reference{table: :categories, name: :foo_bar}, []},
                {:add, :category_2, %Reference{table: :categories, on_delete: :nothing}, []},
                {:add, :category_3, %Reference{table: :categories, on_delete: :delete_all}, [null: false]},
                {:add, :category_4, %Reference{table: :categories, on_delete: :nilify_all}, []}]}

    assert execute_ddl(create) == ["""
    CREATE TABLE `posts` (`id` bigint unsigned not null auto_increment,
    `category_0` BIGINT UNSIGNED,
    CONSTRAINT `posts_category_0_fkey` FOREIGN KEY (`category_0`) REFERENCES `categories`(`id`),
    `category_1` BIGINT UNSIGNED,
    CONSTRAINT `foo_bar` FOREIGN KEY (`category_1`) REFERENCES `categories`(`id`),
    `category_2` BIGINT UNSIGNED,
    CONSTRAINT `posts_category_2_fkey` FOREIGN KEY (`category_2`) REFERENCES `categories`(`id`),
    `category_3` BIGINT UNSIGNED NOT NULL,
    CONSTRAINT `posts_category_3_fkey` FOREIGN KEY (`category_3`) REFERENCES `categories`(`id`) ON DELETE CASCADE,
    `category_4` BIGINT UNSIGNED,
    CONSTRAINT `posts_category_4_fkey` FOREIGN KEY (`category_4`) REFERENCES `categories`(`id`) ON DELETE SET NULL,
    PRIMARY KEY (`id`)) ENGINE = INNODB
    """ |> remove_newlines]
  end

  test "create table with options" do
    create = {:create, table(:posts, options: "WITH FOO=BAR"),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :created_at, :datetime, []}]}
    assert execute_ddl(create) ==
           [~s|CREATE TABLE `posts` (`id` bigint unsigned not null auto_increment, `created_at` datetime, PRIMARY KEY (`id`)) ENGINE = INNODB WITH FOO=BAR|]
  end

  test "create table with both engine and options" do
    create = {:create, table(:posts, engine: :myisam, options: "WITH FOO=BAR"),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :created_at, :datetime, []}]}
    assert execute_ddl(create) ==
           [~s|CREATE TABLE `posts` (`id` bigint unsigned not null auto_increment, `created_at` datetime, PRIMARY KEY (`id`)) ENGINE = MYISAM WITH FOO=BAR|]
  end

  test "create table with composite key" do
    create = {:create, table(:posts),
               [{:add, :a, :integer, [primary_key: true]},
                {:add, :b, :integer, [primary_key: true]},
                {:add, :name, :string, []}]}

    assert execute_ddl(create) == ["""
    CREATE TABLE `posts` (`a` integer, `b` integer, `name` varchar(255), PRIMARY KEY (`a`, `b`)) ENGINE = INNODB
    """ |> remove_newlines]
  end

  test "create table with a map column, and an empty map default" do
    create = {:create, table(:posts),
              [
                {:add, :a, :map, [default: %{}]}
              ]
            }
    assert execute_ddl(create) == [~s|CREATE TABLE `posts` (`a` text DEFAULT '{}') ENGINE = INNODB|]
  end

  test "create table with a map column, and a map default with values" do
    create = {:create, table(:posts),
              [
                {:add, :a, :map, [default: %{foo: "bar", baz: "boom"}]}
              ]
            }
    assert execute_ddl(create) == [~s|CREATE TABLE `posts` (`a` text DEFAULT '{"baz":"boom","foo":"bar"}') ENGINE = INNODB|]
  end

  test "create table with a map column, and a string default" do
    create = {:create, table(:posts),
              [
                {:add, :a, :map, [default: ~s|{"foo":"bar","baz":"boom"}|]}
              ]
            }
    assert execute_ddl(create) == [~s|CREATE TABLE `posts` (`a` text DEFAULT '{"foo":"bar","baz":"boom"}') ENGINE = INNODB|]
  end

  test "create table with time columns" do
    create = {:create, table(:posts),
              [{:add, :published_at, :time, [precision: 3]},
               {:add, :submitted_at, :time, []}]}

    assert execute_ddl(create) == ["""
    CREATE TABLE `posts`
    (`published_at` time,
    `submitted_at` time)
    ENGINE = INNODB
    """ |> remove_newlines]
  end

  test "create table with time_usec columns" do
    create = {:create, table(:posts),
              [{:add, :published_at, :time_usec, [precision: 3]},
               {:add, :submitted_at, :time_usec, []}]}

    assert execute_ddl(create) == ["""
    CREATE TABLE `posts`
    (`published_at` time(3),
    `submitted_at` time(6))
    ENGINE = INNODB
    """ |> remove_newlines]
  end

  test "create table with utc_datetime columns" do
    create = {:create, table(:posts),
              [{:add, :published_at, :utc_datetime, [precision: 3]},
               {:add, :submitted_at, :utc_datetime, []}]}

    assert execute_ddl(create) == ["""
    CREATE TABLE `posts`
    (`published_at` datetime,
    `submitted_at` datetime)
    ENGINE = INNODB
    """ |> remove_newlines]
  end

  test "create table with utc_datetime_usec columns" do
    create = {:create, table(:posts),
              [{:add, :published_at, :utc_datetime_usec, [precision: 3]},
               {:add, :submitted_at, :utc_datetime_usec, []}]}

    assert execute_ddl(create) == ["""
    CREATE TABLE `posts`
    (`published_at` datetime(3),
    `submitted_at` datetime(6))
    ENGINE = INNODB
    """ |> remove_newlines]
  end

  test "create table with naive_datetime columns" do
    create = {:create, table(:posts),
              [{:add, :published_at, :naive_datetime, [precision: 3]},
               {:add, :submitted_at, :naive_datetime, []}]}

    assert execute_ddl(create) == ["""
    CREATE TABLE `posts`
    (`published_at` datetime,
    `submitted_at` datetime)
    ENGINE = INNODB
    """ |> remove_newlines]
  end

  test "create table with naive_datetime_usec columns" do
    create = {:create, table(:posts),
              [{:add, :published_at, :naive_datetime_usec, [precision: 3]},
               {:add, :submitted_at, :naive_datetime_usec, []}]}

    assert execute_ddl(create) == ["""
    CREATE TABLE `posts`
    (`published_at` datetime(3),
    `submitted_at` datetime(6))
    ENGINE = INNODB
    """ |> remove_newlines]
  end

  test "drop table" do
    drop = {:drop, table(:posts)}
    assert execute_ddl(drop) == [~s|DROP TABLE `posts`|]
  end

  test "drop table with prefixes" do
    drop = {:drop, table(:posts, prefix: :foo)}
    assert execute_ddl(drop) == [~s|DROP TABLE `foo`.`posts`|]
  end

  test "alter table" do
    alter = {:alter, table(:posts),
               [{:add, :title, :string, [default: "Untitled", size: 100, null: false]},
                {:add, :author_id, %Reference{table: :author}, []},
                {:modify, :price, :numeric, [precision: 8, scale: 2, null: true]},
                {:modify, :cost, :integer, [null: false, default: nil]},
                {:modify, :permalink_id, %Reference{table: :permalinks}, null: false},
                {:modify, :status, :string, from: :integer},
                {:modify, :user_id, :integer, from: %Reference{table: :users}},
                {:modify, :group_id, %Reference{table: :groups, column: :gid}, from: %Reference{table: :groups}},
                {:remove, :summary}]}

    assert execute_ddl(alter) == ["""
    ALTER TABLE `posts` ADD `title` varchar(100) DEFAULT 'Untitled' NOT NULL,
    ADD `author_id` BIGINT UNSIGNED,
    ADD CONSTRAINT `posts_author_id_fkey` FOREIGN KEY (`author_id`) REFERENCES `author`(`id`),
    MODIFY `price` numeric(8,2) NULL, MODIFY `cost` integer DEFAULT NULL NOT NULL,
    MODIFY `permalink_id` BIGINT UNSIGNED NOT NULL,
    ADD CONSTRAINT `posts_permalink_id_fkey` FOREIGN KEY (`permalink_id`) REFERENCES `permalinks`(`id`),
    MODIFY `status` varchar(255),
    DROP FOREIGN KEY `posts_user_id_fkey`,
    MODIFY `user_id` integer,
    DROP FOREIGN KEY `posts_group_id_fkey`,
    MODIFY `group_id` BIGINT UNSIGNED,
    ADD CONSTRAINT `posts_group_id_fkey` FOREIGN KEY (`group_id`) REFERENCES `groups`(`gid`),
    DROP `summary`
    """ |> remove_newlines]
  end

  test "alter table with prefix" do
    alter = {:alter, table(:posts, prefix: :foo),
               [{:add, :author_id, %Reference{table: :author}, []},
                {:modify, :permalink_id, %Reference{table: :permalinks}, null: false}]}

    assert execute_ddl(alter) == ["""
    ALTER TABLE `foo`.`posts` ADD `author_id` BIGINT UNSIGNED,
    ADD CONSTRAINT `posts_author_id_fkey` FOREIGN KEY (`author_id`) REFERENCES `foo`.`author`(`id`),
    MODIFY `permalink_id` BIGINT UNSIGNED NOT NULL,
    ADD CONSTRAINT `posts_permalink_id_fkey` FOREIGN KEY (`permalink_id`) REFERENCES `foo`.`permalinks`(`id`)
    """ |> remove_newlines]
  end

  test "alter table with primary key" do
    alter = {:alter, table(:posts),
               [{:add, :my_pk, :serial, [primary_key: true]}]}

    assert execute_ddl(alter) == ["""
    ALTER TABLE `posts`
    ADD `my_pk` bigint unsigned not null auto_increment,
    ADD PRIMARY KEY (`my_pk`)
    """ |> remove_newlines]
  end

  test "create index" do
    create = {:create, index(:posts, [:category_id, :permalink])}
    assert execute_ddl(create) ==
           [~s|CREATE INDEX `posts_category_id_permalink_index` ON `posts` (`category_id`, `permalink`)|]

    create = {:create, index(:posts, ["permalink(8)"], name: "posts$main")}
    assert execute_ddl(create) ==
           [~s|CREATE INDEX `posts$main` ON `posts` (permalink(8))|]
  end

  test "create index with prefix" do
    create = {:create, index(:posts, [:category_id, :permalink], prefix: :foo)}
    assert execute_ddl(create) ==
           [~s|CREATE INDEX `posts_category_id_permalink_index` ON `foo`.`posts` (`category_id`, `permalink`)|]
  end

  test "create index asserting concurrency" do
    create = {:create, index(:posts, ["permalink(8)"], name: "posts$main", concurrently: true)}
    assert execute_ddl(create) ==
           [~s|CREATE INDEX `posts$main` ON `posts` (permalink(8)) LOCK=NONE|]
  end

  test "create unique index" do
    create = {:create, index(:posts, [:permalink], unique: true)}
    assert execute_ddl(create) ==
           [~s|CREATE UNIQUE INDEX `posts_permalink_index` ON `posts` (`permalink`)|]
  end

  test "create unique index with condition" do
    assert_raise ArgumentError, "MySQL adapter does not support where in indexes", fn ->
      create = {:create, index(:posts, [:permalink], unique: true, where: "public IS TRUE")}
      execute_ddl(create)
    end
  end

  test "create constraints" do
    assert_raise ArgumentError, "MySQL adapter does not support check constraints", fn ->
      create = {:create, constraint(:products, "foo", check: "price")}
      assert execute_ddl(create)
    end

    assert_raise ArgumentError, "MySQL adapter does not support exclusion constraints", fn ->
      create = {:create, constraint(:products, "bar", exclude: "price")}
      assert execute_ddl(create)
    end
  end

  test "create an index using a different type" do
    create = {:create, index(:posts, [:permalink], using: :hash)}
    assert execute_ddl(create) ==
           [~s|CREATE INDEX `posts_permalink_index` ON `posts` (`permalink`) USING hash|]
  end

  test "drop index" do
    drop = {:drop, index(:posts, [:id], name: "posts$main")}
    assert execute_ddl(drop) == [~s|DROP INDEX `posts$main` ON `posts`|]
  end

  test "drop index with prefix" do
    drop = {:drop, index(:posts, [:id], name: "posts$main", prefix: :foo)}
    assert execute_ddl(drop) == [~s|DROP INDEX `posts$main` ON `foo`.`posts`|]
  end

  test "drop index asserting concurrency" do
    drop = {:drop, index(:posts, [:id], name: "posts$main", concurrently: true)}
    assert execute_ddl(drop) == [~s|DROP INDEX `posts$main` ON `posts` LOCK=NONE|]
  end

  test "rename table" do
    rename = {:rename, table(:posts), table(:new_posts)}
    assert execute_ddl(rename) == [~s|RENAME TABLE `posts` TO `new_posts`|]
  end

  test "rename table with prefix" do
    rename = {:rename, table(:posts, prefix: :foo), table(:new_posts, prefix: :foo)}
    assert execute_ddl(rename) == [~s|RENAME TABLE `foo`.`posts` TO `foo`.`new_posts`|]
  end

  # Unsupported types and clauses

  test "lateral join with fragment" do
    assert_raise Ecto.QueryError, ~r"join `:inner_lateral` not supported by MySQL", fn ->
      Schema
      |> join(:inner_lateral, [p], q in fragment("SELECT * FROM schema2 AS s2 WHERE s2.id = ? AND s2.field = ?", p.x, ^10))
      |> select([p, q], {p.id, q.z})
      |> plan()
      |> all
    end
  end

  test "arrays" do
    assert_raise Ecto.QueryError, ~r"Array type is not supported by MySQL", fn ->
      query = Schema |> select([], fragment("?", [1, 2, 3])) |> plan()
      all(query)
    end
  end

  defp remove_newlines(string) do
    string |> String.trim |> String.replace("\n", " ")
  end
end
