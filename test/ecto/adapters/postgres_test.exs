Code.require_file "../../../integration_test/support/types.exs", __DIR__

defmodule Ecto.Adapters.PostgresTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Ecto.Queryable
  alias Ecto.Adapters.Postgres.Connection, as: SQL

  defmodule Model do
    use Ecto.Schema

    schema "model" do
      field :x, :integer
      field :y, :integer
      field :z, :integer
      field :w, {:array, :integer}

      has_many :comments, Ecto.Adapters.PostgresTest.Model2,
        references: :x,
        foreign_key: :z
      has_one :permalink, Ecto.Adapters.PostgresTest.Model3,
        references: :y,
        foreign_key: :id
    end
  end

  defmodule Model2 do
    use Ecto.Schema

    schema "model2" do
      belongs_to :post, Ecto.Adapters.PostgresTest.Model,
        references: :x,
        foreign_key: :z
    end
  end

  defmodule Model3 do
    use Ecto.Schema

    schema "model3" do
      field :list1, {:array, :string}
      field :list2, {:array, :integer}
      field :binary, :binary
    end
  end

  defp normalize(query, operation \\ :all) do
    {query, _params, _key} = Ecto.Query.Planner.prepare(query, operation, Ecto.Adapters.Postgres)
    Ecto.Query.Planner.normalize(query, operation, Ecto.Adapters.Postgres)
  end

  test "from" do
    query = Model |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0}
  end

  test "from without schema" do
    query = "posts" |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT p0."x" FROM "posts" AS p0}

    assert_raise Ecto.QueryError, ~r"PostgreSQL requires a schema module", fn ->
      SQL.all from(p in "posts", select: p) |> normalize()
    end
  end

  test "select" do
    query = Model |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x", m0."y" FROM "model" AS m0}

    query = Model |> select([r], [r.x, r.y]) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x", m0."y" FROM "model" AS m0}

    query = Model |> select([r], take(r, [:x, :y])) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x", m0."y" FROM "model" AS m0}
  end

  test "aggregates" do
    query = Model |> select([r], count(r.x)) |> normalize
    assert SQL.all(query) == ~s{SELECT count(m0."x") FROM "model" AS m0}

    query = Model |> select([r], count(r.x, :distinct)) |> normalize
    assert SQL.all(query) == ~s{SELECT count(DISTINCT m0."x") FROM "model" AS m0}
  end

  test "distinct" do
    query = Model |> distinct([r], r.x) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT DISTINCT ON (m0."x") m0."x", m0."y" FROM "model" AS m0}

    query = Model |> distinct([r], 2) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT DISTINCT ON (2) m0."x" FROM "model" AS m0}

    query = Model |> distinct([r], [r.x, r.y]) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT DISTINCT ON (m0."x", m0."y") m0."x", m0."y" FROM "model" AS m0}

    query = Model |> distinct([r], true) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT DISTINCT m0."x", m0."y" FROM "model" AS m0}

    query = Model |> distinct([r], false) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x", m0."y" FROM "model" AS m0}

    query = Model |> distinct(true) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT DISTINCT m0."x", m0."y" FROM "model" AS m0}

    query = Model |> distinct(false) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x", m0."y" FROM "model" AS m0}
  end

  test "where" do
    query = Model |> where([r], r.x == 42) |> where([r], r.y != 43) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 WHERE (m0."x" = 42) AND (m0."y" != 43)}
  end

  test "order by" do
    query = Model |> order_by([r], r.x) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 ORDER BY m0."x"}

    query = Model |> order_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 ORDER BY m0."x", m0."y"}

    query = Model |> order_by([r], [asc: r.x, desc: r.y]) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 ORDER BY m0."x", m0."y" DESC}

    query = Model |> order_by([r], [r.y]) |> distinct([r], r.x) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT DISTINCT ON (m0."x") m0."x" FROM "model" AS m0 ORDER BY m0."x", m0."y"}

    query = Model |> order_by([r], []) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0}
  end

  test "limit and offset" do
    query = Model |> limit([r], 3) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM "model" AS m0 LIMIT 3}

    query = Model |> offset([r], 5) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM "model" AS m0 OFFSET 5}

    query = Model |> offset([r], 5) |> limit([r], 3) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM "model" AS m0 LIMIT 3 OFFSET 5}
  end

  test "lock" do
    query = Model |> lock("FOR SHARE NOWAIT") |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM "model" AS m0 FOR SHARE NOWAIT}
  end

  test "string escape" do
    query = "model" |> where(foo: "'\\  ") |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM \"model\" AS m0 WHERE (m0.\"foo\" = '''\\  ')}

    query = "model" |> where(foo: "'") |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM "model" AS m0 WHERE (m0."foo" = '''')}
  end

  test "binary ops" do
    query = Model |> select([r], r.x == 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" = 2 FROM "model" AS m0}

    query = Model |> select([r], r.x != 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" != 2 FROM "model" AS m0}

    query = Model |> select([r], r.x <= 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" <= 2 FROM "model" AS m0}

    query = Model |> select([r], r.x >= 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" >= 2 FROM "model" AS m0}

    query = Model |> select([r], r.x < 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" < 2 FROM "model" AS m0}

    query = Model |> select([r], r.x > 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" > 2 FROM "model" AS m0}
  end

  test "is_nil" do
    query = Model |> select([r], is_nil(r.x)) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" IS NULL FROM "model" AS m0}

    query = Model |> select([r], not is_nil(r.x)) |> normalize
    assert SQL.all(query) == ~s{SELECT NOT (m0."x" IS NULL) FROM "model" AS m0}
  end

  test "fragments" do
    query = Model |> select([r], fragment("now")) |> normalize
    assert SQL.all(query) == ~s{SELECT now FROM "model" AS m0}

    query = Model |> select([r], fragment("downcase(?)", r.x)) |> normalize
    assert SQL.all(query) == ~s{SELECT downcase(m0."x") FROM "model" AS m0}

    value = 13
    query = Model |> select([r], fragment("downcase(?, ?)", r.x, ^value)) |> normalize
    assert SQL.all(query) == ~s{SELECT downcase(m0."x", $1) FROM "model" AS m0}

    query = Model |> select([], fragment(title: 2)) |> normalize
    assert_raise Ecto.QueryError, fn ->
      SQL.all(query)
    end
  end

  test "literals" do
    query = "model" |> where(foo: true) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM "model" AS m0 WHERE (m0."foo" = TRUE)}

    query = "model" |> where(foo: false) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM "model" AS m0 WHERE (m0."foo" = FALSE)}

    query = "model" |> where(foo: "abc") |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM "model" AS m0 WHERE (m0."foo" = 'abc')}

    query = "model" |> where(foo: <<0,?a,?b,?c>>) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM "model" AS m0 WHERE (m0."foo" = '\\x00616263'::bytea)}

    query = "model" |> where(foo: 123) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM "model" AS m0 WHERE (m0."foo" = 123)}

    query = "model" |> where(foo: 123.0) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM "model" AS m0 WHERE (m0."foo" = 123.0::float)}
  end

  test "tagged type" do
    query = Model |> select([], type(^"601d74e4-a8d3-4b6e-8365-eddb4c893327", Ecto.UUID)) |> normalize
    assert SQL.all(query) == ~s{SELECT $1::uuid FROM "model" AS m0}

    query = Model |> select([], type(^1, Custom.Permalink)) |> normalize
    assert SQL.all(query) == ~s{SELECT $1::integer FROM "model" AS m0}

    query = Model |> select([], type(^[1,2,3], {:array, Custom.Permalink})) |> normalize
    assert SQL.all(query) == ~s{SELECT $1::integer[] FROM "model" AS m0}
  end

  test "nested expressions" do
    z = 123
    query = from(r in Model, []) |> select([r], r.x > 0 and (r.y > ^(-z)) or true) |> normalize
    assert SQL.all(query) == ~s{SELECT ((m0."x" > 0) AND (m0."y" > $1)) OR TRUE FROM "model" AS m0}
  end

  test "in expression" do
    query = Model |> select([e], 1 in []) |> normalize
    assert SQL.all(query) == ~s{SELECT false FROM "model" AS m0}

    query = Model |> select([e], 1 in [1,e.x,3]) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 IN (1,m0."x",3) FROM "model" AS m0}

    query = Model |> select([e], 1 in ^[]) |> normalize
    assert SQL.all(query) == ~s{SELECT false FROM "model" AS m0}

    query = Model |> select([e], 1 in ^[1, 2, 3]) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 IN ($1,$2,$3) FROM "model" AS m0}

    query = Model |> select([e], 1 in [1, ^2, 3]) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 IN (1,$1,3) FROM "model" AS m0}

    query = Model |> select([e], 1 in e.w) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 = ANY(m0."w") FROM "model" AS m0}

    query = Model |> select([e], 1 in fragment("foo")) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 = ANY(foo) FROM "model" AS m0}
  end

  test "having" do
    query = Model |> having([p], p.x == p.x) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM "model" AS m0 HAVING (m0."x" = m0."x")}

    query = Model |> having([p], p.x == p.x) |> having([p], p.y == p.y) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM "model" AS m0 HAVING (m0."x" = m0."x") AND (m0."y" = m0."y")}
  end

  test "group by" do
    query = Model |> group_by([r], r.x) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 GROUP BY m0."x"}

    query = Model |> group_by([r], 2) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 GROUP BY 2}

    query = Model |> group_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0 GROUP BY m0."x", m0."y"}

    query = Model |> group_by([r], []) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0."x" FROM "model" AS m0}
  end

  test "arrays and sigils" do
    query = Model |> select([], fragment("?", [1, 2, 3])) |> normalize
    assert SQL.all(query) == ~s{SELECT ARRAY[1,2,3] FROM "model" AS m0}

    query = Model |> select([], fragment("?", ~w(abc def))) |> normalize
    assert SQL.all(query) == ~s{SELECT ARRAY['abc','def'] FROM "model" AS m0}
  end

  test "interpolated values" do
    query = "model"
            |> select([], ^0)
            |> join(:inner, [], Model2, ^true)
            |> join(:inner, [], Model2, ^false)
            |> where([], fragment("?", ^true))
            |> where([], fragment("?", ^false))
            |> having([], fragment("?", ^true))
            |> having([], fragment("?", ^false))
            |> group_by([], fragment("?", ^1))
            |> group_by([], fragment("?", ^2))
            |> order_by([], fragment("?", ^3))
            |> order_by([], ^:x)
            |> limit([], ^4)
            |> offset([], ^5)
            |> normalize

    result =
      "SELECT $1 FROM \"model\" AS m0 INNER JOIN \"model2\" AS m1 ON $2 " <>
      "INNER JOIN \"model2\" AS m2 ON $3 WHERE ($4) AND ($5) " <>
      "GROUP BY $6, $7 HAVING ($8) AND ($9) " <>
      "ORDER BY $10, m0.\"x\" LIMIT $11 OFFSET $12"

    assert SQL.all(query) == String.rstrip(result)
  end

  test "fragments and types" do
    query =
      normalize from(e in "model",
        where: fragment("extract(? from ?) = ?", ^"month", e.start_time, type(^"4", :integer)),
        where: fragment("extract(? from ?) = ?", ^"year", e.start_time, type(^"2015", :integer)),
        select: true)

    result =
      "SELECT TRUE FROM \"model\" AS m0 " <>
      "WHERE (extract($1 from m0.\"start_time\") = $2::integer) " <>
      "AND (extract($3 from m0.\"start_time\") = $4::integer)"

    assert SQL.all(query) == String.rstrip(result)
  end

  test "fragments allow ? to be escaped with backslash" do
    query =
      normalize  from(e in "model",
        where: fragment("? = \"query\\?\"", e.start_time),
        select: true)

    result =
      "SELECT TRUE FROM \"model\" AS m0 " <>
      "WHERE (m0.\"start_time\" = \"query?\")"

    assert SQL.all(query) == String.rstrip(result)
  end

  ## *_all

  test "update all" do
    query = from(m in Model, update: [set: [x: 0]]) |> normalize(:update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE "model" AS m0 SET "x" = 0}

    query = from(m in Model, update: [set: [x: 0], inc: [y: 1, z: -3]]) |> normalize(:update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE "model" AS m0 SET "x" = 0, "y" = "y" + 1, "z" = "z" + -3}

    query = from(e in Model, where: e.x == 123, update: [set: [x: 0]]) |> normalize(:update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE "model" AS m0 SET "x" = 0 WHERE (m0."x" = 123)}

    query = from(m in Model, update: [set: [x: 0, y: "123"]]) |> normalize(:update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE "model" AS m0 SET "x" = 0, "y" = 123}

    query = from(m in Model, update: [set: [x: ^0]]) |> normalize(:update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE "model" AS m0 SET "x" = $1}

    query = Model |> join(:inner, [p], q in Model2, p.x == q.z)
                  |> update([_], set: [x: 0]) |> normalize(:update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE "model" AS m0 SET "x" = 0 FROM "model2" AS m1 WHERE (m0."x" = m1."z")}

    query = from(e in Model, where: e.x == 123, update: [set: [x: 0]],
                             join: q in Model2, on: e.x == q.z) |> normalize(:update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE "model" AS m0 SET "x" = 0 FROM "model2" AS m1 } <>
           ~s{WHERE (m0."x" = m1."z") AND (m0."x" = 123)}
  end

  test "update all array ops" do
    query = from(m in Model, update: [push: [w: 0]]) |> normalize(:update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE "model" AS m0 SET "w" = array_append("w", 0)}

    query = from(m in Model, update: [pull: [w: 0]]) |> normalize(:update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE "model" AS m0 SET "w" = array_remove("w", 0)}
  end

  test "update all with prefix" do
    query = from(m in Model, update: [set: [x: 0]]) |> normalize(:update_all)
    assert SQL.update_all(%{query | prefix: "prefix"}) ==
           ~s{UPDATE "prefix"."model" AS m0 SET "x" = 0}
  end

  test "delete all" do
    query = Model |> Queryable.to_query |> normalize
    assert SQL.delete_all(query) == ~s{DELETE FROM "model" AS m0}

    query = from(e in Model, where: e.x == 123) |> normalize
    assert SQL.delete_all(query) ==
           ~s{DELETE FROM "model" AS m0 WHERE (m0."x" = 123)}

    query = Model |> join(:inner, [p], q in Model2, p.x == q.z) |> normalize
    assert SQL.delete_all(query) ==
           ~s{DELETE FROM "model" AS m0 USING "model2" AS m1 WHERE m0."x" = m1."z"}

    query = from(e in Model, where: e.x == 123, join: q in Model2, on: e.x == q.z) |> normalize
    assert SQL.delete_all(query) ==
           ~s{DELETE FROM "model" AS m0 USING "model2" AS m1 WHERE m0."x" = m1."z" AND (m0."x" = 123)}
  end

  test "delete all with prefix" do
    query = Model |> Queryable.to_query |> normalize
    assert SQL.delete_all(%{query | prefix: "prefix"}) == ~s{DELETE FROM "prefix"."model" AS m0}
  end

  ## Joins

  test "join" do
    query = Model |> join(:inner, [p], q in Model2, p.x == q.z) |> select([], true) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT TRUE FROM "model" AS m0 INNER JOIN "model2" AS m1 ON m0."x" = m1."z"}

    query = Model |> join(:inner, [p], q in Model2, p.x == q.z)
                  |> join(:inner, [], Model, true) |> select([], true) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT TRUE FROM "model" AS m0 INNER JOIN "model2" AS m1 ON m0."x" = m1."z" } <>
           ~s{INNER JOIN "model" AS m2 ON TRUE}
  end

  test "join with nothing bound" do
    query = Model |> join(:inner, [], q in Model2, q.z == q.z) |> select([], true) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT TRUE FROM "model" AS m0 INNER JOIN "model2" AS m1 ON m1."z" = m1."z"}
  end

  test "join without model" do
    query = "posts" |> join(:inner, [p], q in "comments", p.x == q.z) |> select([], true) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT TRUE FROM "posts" AS p0 INNER JOIN "comments" AS c1 ON p0."x" = c1."z"}
  end

  test "join with prefix" do
    query = Model |> join(:inner, [p], q in Model2, p.x == q.z) |> select([], true) |> normalize
    assert SQL.all(%{query | prefix: "prefix"}) ==
           ~s{SELECT TRUE FROM "prefix"."model" AS m0 INNER JOIN "prefix"."model2" AS m1 ON m0."x" = m1."z"}
  end

  test "join with fragment" do
    query = Model
            |> join(:inner, [p], q in fragment("SELECT * FROM model2 AS m2 WHERE m2.id = ? AND m2.field = ?", p.x, ^10))
            |> select([p], {p.id, ^0})
            |> where([p], p.id > 0 and p.id < ^100)
            |> normalize
    assert SQL.all(query) ==
           ~s{SELECT m0."id", $1 FROM "model" AS m0 INNER JOIN } <>
           ~s{(SELECT * FROM model2 AS m2 WHERE m2.id = m0."x" AND m2.field = $2) AS f1 ON TRUE } <>
           ~s{WHERE ((m0."id" > 0) AND (m0."id" < $3))}
  end

  test "join with fragment and on defined" do
    query = Model
            |> join(:inner, [p], q in fragment("SELECT * FROM model2"), q.id == p.id)
            |> select([p], {p.id, ^0})
            |> normalize
    assert SQL.all(query) ==
           ~s{SELECT m0."id", $1 FROM "model" AS m0 INNER JOIN } <>
           ~s{(SELECT * FROM model2) AS f1 ON f1."id" = m0."id"}
  end

  ## Associations

  test "association join belongs_to" do
    query = Model2 |> join(:inner, [c], p in assoc(c, :post)) |> select([], true) |> normalize
    assert SQL.all(query) ==
           "SELECT TRUE FROM \"model2\" AS m0 INNER JOIN \"model\" AS m1 ON m1.\"x\" = m0.\"z\""
  end

  test "association join has_many" do
    query = Model |> join(:inner, [p], c in assoc(p, :comments)) |> select([], true) |> normalize
    assert SQL.all(query) ==
           "SELECT TRUE FROM \"model\" AS m0 INNER JOIN \"model2\" AS m1 ON m1.\"z\" = m0.\"x\""
  end

  test "association join has_one" do
    query = Model |> join(:inner, [p], pp in assoc(p, :permalink)) |> select([], true) |> normalize
    assert SQL.all(query) ==
           "SELECT TRUE FROM \"model\" AS m0 INNER JOIN \"model3\" AS m1 ON m1.\"id\" = m0.\"y\""
  end

  test "join produces correct bindings" do
    query = from(p in Model, join: c in Model2, on: true)
    query = from(p in query, join: c in Model2, on: true, select: {p.id, c.id})
    query = normalize(query)
    assert SQL.all(query) ==
           "SELECT m0.\"id\", m2.\"id\" FROM \"model\" AS m0 INNER JOIN \"model2\" AS m1 ON TRUE INNER JOIN \"model2\" AS m2 ON TRUE"
  end

  # Schema based

  test "insert" do
    query = SQL.insert(nil, "model", [:x, :y], [[:x, :y]], [:id])
    assert query == ~s{INSERT INTO "model" ("x","y") VALUES ($1,$2) RETURNING "id"}

    query = SQL.insert(nil, "model", [:x, :y], [[:x, :y], [nil, :z]], [:id])
    assert query == ~s{INSERT INTO "model" ("x","y") VALUES ($1,$2),(DEFAULT,$3) RETURNING "id"}

    query = SQL.insert(nil, "model", [], [[]], [:id])
    assert query == ~s{INSERT INTO "model" VALUES (DEFAULT) RETURNING "id"}

    query = SQL.insert(nil, "model", [], [[]], [])
    assert query == ~s{INSERT INTO "model" VALUES (DEFAULT)}

    query = SQL.insert("prefix", "model", [], [[]], [])
    assert query == ~s{INSERT INTO "prefix"."model" VALUES (DEFAULT)}
  end

  test "update" do
    query = SQL.update(nil, "model", [:x, :y], [:id], [])
    assert query == ~s{UPDATE "model" SET "x" = $1, "y" = $2 WHERE "id" = $3}

    query = SQL.update(nil, "model", [:x, :y], [:id], [:z])
    assert query == ~s{UPDATE "model" SET "x" = $1, "y" = $2 WHERE "id" = $3 RETURNING "z"}

    query = SQL.update("prefix", "model", [:x, :y], [:id], [])
    assert query == ~s{UPDATE "prefix"."model" SET "x" = $1, "y" = $2 WHERE "id" = $3}
  end

  test "delete" do
    query = SQL.delete(nil, "model", [:x, :y], [])
    assert query == ~s{DELETE FROM "model" WHERE "x" = $1 AND "y" = $2}

    query = SQL.delete(nil, "model", [:x, :y], [:z])
    assert query == ~s{DELETE FROM "model" WHERE "x" = $1 AND "y" = $2 RETURNING "z"}

    query = SQL.delete("prefix", "model", [:x, :y], [])
    assert query == ~s{DELETE FROM "prefix"."model" WHERE "x" = $1 AND "y" = $2}
  end

  # DDL

  import Ecto.Migration, only: [table: 1, table: 2, index: 2, index: 3, references: 1, references: 2]

  test "executing a string during migration" do
    assert SQL.execute_ddl("example") == "example"
  end

  test "create table" do
    create = {:create, table(:posts),
               [{:add, :name, :string, [default: "Untitled", size: 20, null: false]},
                {:add, :price, :numeric, [precision: 8, scale: 2, default: {:fragment, "expr"}]},
                {:add, :on_hand, :integer, [default: 0, null: true]},
                {:add, :is_active, :boolean, [default: true]},
                {:add, :tags, {:array, :string}, [default: []]}]}

    assert SQL.execute_ddl(create) == """
    CREATE TABLE "posts" ("name" varchar(20) DEFAULT 'Untitled' NOT NULL,
    "price" numeric(8,2) DEFAULT expr,
    "on_hand" integer DEFAULT 0 NULL,
    "is_active" boolean DEFAULT true,
    "tags" varchar(255)[] DEFAULT ARRAY[]::varchar[])
    """ |> remove_newlines
  end

  test "create table with prefix" do
    create = {:create, table(:posts, prefix: :foo),
               [{:add, :category_0, references(:categories), []}]}

    assert SQL.execute_ddl(create) == """
    CREATE TABLE "foo"."posts"
    ("category_0" integer CONSTRAINT "posts_category_0_fkey" REFERENCES "foo"."categories"("id"))
    """ |> remove_newlines
  end

  test "create table with references" do
    create = {:create, table(:posts),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :category_0, references(:categories), []},
                {:add, :category_1, references(:categories, name: :foo_bar), []},
                {:add, :category_2, references(:categories, on_delete: :nothing), []},
                {:add, :category_3, references(:categories, on_delete: :delete_all), [null: false]},
                {:add, :category_4, references(:categories, on_delete: :nilify_all), []}]}

    assert SQL.execute_ddl(create) == """
    CREATE TABLE "posts" ("id" serial PRIMARY KEY,
    "category_0" integer CONSTRAINT "posts_category_0_fkey" REFERENCES "categories"("id"),
    "category_1" integer CONSTRAINT "foo_bar" REFERENCES "categories"("id"),
    "category_2" integer CONSTRAINT "posts_category_2_fkey" REFERENCES "categories"("id"),
    "category_3" integer NOT NULL CONSTRAINT "posts_category_3_fkey" REFERENCES "categories"("id") ON DELETE CASCADE,
    "category_4" integer CONSTRAINT "posts_category_4_fkey" REFERENCES "categories"("id") ON DELETE SET NULL)
    """ |> remove_newlines
  end

  test "create table with options" do
    create = {:create, table(:posts, [options: "WITH FOO=BAR"]),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :created_at, :datetime, []}]}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE TABLE "posts" ("id" serial PRIMARY KEY, "created_at" timestamp) WITH FOO=BAR|
  end

  test "drop table" do
    drop = {:drop, table(:posts)}
    assert SQL.execute_ddl(drop) == ~s|DROP TABLE "posts"|
  end

  test "drop table with prefix" do
    drop = {:drop, table(:posts, prefix: :foo)}
    assert SQL.execute_ddl(drop) == ~s|DROP TABLE "foo"."posts"|
  end

  test "alter table" do
    alter = {:alter, table(:posts),
               [{:add, :title, :string, [default: "Untitled", size: 100, null: false]},
                {:add, :author_id, references(:author), []},
                {:modify, :price, :numeric, [precision: 8, scale: 2, null: true]},
                {:modify, :cost, :integer, [null: false, default: nil]},
                {:modify, :permalink_id, references(:permalinks), null: false},
                {:remove, :summary}]}

    assert SQL.execute_ddl(alter) == """
    ALTER TABLE "posts"
    ADD COLUMN "title" varchar(100) DEFAULT 'Untitled' NOT NULL,
    ADD COLUMN "author_id" integer CONSTRAINT "posts_author_id_fkey" REFERENCES "author"("id"),
    ALTER COLUMN "price" TYPE numeric(8,2) ,
    ALTER COLUMN "price" DROP NOT NULL,
    ALTER COLUMN "cost" TYPE integer ,
    ALTER COLUMN "cost" SET NOT NULL ,
    ALTER COLUMN "cost" SET DEFAULT NULL,
    ALTER COLUMN "permalink_id" TYPE integer ,
    ADD CONSTRAINT "posts_permalink_id_fkey" FOREIGN KEY ("permalink_id") REFERENCES "permalinks"("id") ,
    ALTER COLUMN "permalink_id" SET NOT NULL,
    DROP COLUMN "summary"
    """ |> remove_newlines
  end

  test "alter table with prefix" do
    alter = {:alter, table(:posts, prefix: :foo),
               [{:add, :author_id, references(:author, prefix: :foo), []},
                {:modify, :permalink_id, references(:permalinks, prefix: :foo), null: false}]}

    assert SQL.execute_ddl(alter) == """
    ALTER TABLE "foo"."posts"
    ADD COLUMN "author_id" integer CONSTRAINT "posts_author_id_fkey" REFERENCES "foo"."author"("id"),
    ALTER COLUMN \"permalink_id\" TYPE integer ,
    ADD CONSTRAINT "posts_permalink_id_fkey" FOREIGN KEY ("permalink_id") REFERENCES "foo"."permalinks"("id") ,
    ALTER COLUMN "permalink_id" SET NOT NULL
    """ |> remove_newlines
  end

  test "create index" do
    create = {:create, index(:posts, [:category_id, :permalink])}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE INDEX "posts_category_id_permalink_index" ON "posts" ("category_id", "permalink")|

    create = {:create, index(:posts, ["lower(permalink)"], name: "posts$main")}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE INDEX "posts$main" ON "posts" (lower(permalink))|
  end

  test "create index with prefix" do
    create = {:create, index(:posts, [:category_id, :permalink], prefix: :foo)}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE INDEX "posts_category_id_permalink_index" ON "foo"."posts" ("category_id", "permalink")|

    create = {:create, index(:posts, ["lower(permalink)"], name: "posts$main", prefix: :foo)}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE INDEX "posts$main" ON "foo"."posts" (lower(permalink))|
  end

  test "create unique index" do
    create = {:create, index(:posts, [:permalink], unique: true)}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE UNIQUE INDEX "posts_permalink_index" ON "posts" ("permalink")|
  end

  test "create unique index with condition" do
    create = {:create, index(:posts, [:permalink], unique: true, where: "public IS TRUE")}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE UNIQUE INDEX "posts_permalink_index" ON "posts" ("permalink") WHERE public IS TRUE|

    create = {:create, index(:posts, [:permalink], unique: true, where: :public)}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE UNIQUE INDEX "posts_permalink_index" ON "posts" ("permalink") WHERE public|
  end

  test "create index concurrently" do
    create = {:create, index(:posts, [:permalink], concurrently: true)}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE INDEX CONCURRENTLY "posts_permalink_index" ON "posts" ("permalink")|
  end

  test "create unique index concurrently" do
    create = {:create, index(:posts, [:permalink], concurrently: true, unique: true)}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE UNIQUE INDEX CONCURRENTLY "posts_permalink_index" ON "posts" ("permalink")|
  end

  test "create an index using a different type" do
    create = {:create, index(:posts, [:permalink], using: :hash)}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE INDEX "posts_permalink_index" ON "posts" USING hash ("permalink")|
  end

  test "drop index" do
    drop = {:drop, index(:posts, [:id], name: "posts$main")}
    assert SQL.execute_ddl(drop) == ~s|DROP INDEX "posts$main"|
  end

  test "drop index with prefix" do
    drop = {:drop, index(:posts, [:id], name: "posts$main", prefix: :foo)}
    assert SQL.execute_ddl(drop) == ~s|DROP INDEX "foo"."posts$main"|
  end

  test "drop index concurrently" do
    drop = {:drop, index(:posts, [:id], name: "posts$main", concurrently: true)}
    assert SQL.execute_ddl(drop) == ~s|DROP INDEX CONCURRENTLY "posts$main"|
  end

  test "rename table" do
    rename = {:rename, table(:posts), table(:new_posts)}
    assert SQL.execute_ddl(rename) == ~s|ALTER TABLE "posts" RENAME TO "new_posts"|
  end

  test "rename table with prefix" do
    rename = {:rename, table(:posts, prefix: :foo), table(:new_posts, prefix: :foo)}
    assert SQL.execute_ddl(rename) == ~s|ALTER TABLE "foo"."posts" RENAME TO "foo"."new_posts"|
  end

  test "rename column" do
    rename = {:rename, table(:posts), :given_name, :first_name}
    assert SQL.execute_ddl(rename) == ~s|ALTER TABLE "posts" RENAME "given_name" TO "first_name"|
  end

  test "rename column in prefixed table" do
    rename = {:rename, table(:posts, prefix: :foo), :given_name, :first_name}
    assert SQL.execute_ddl(rename) == ~s|ALTER TABLE "foo"."posts" RENAME "given_name" TO "first_name"|
  end

  defp remove_newlines(string) do
    string |> String.strip |> String.replace("\n", " ")
  end
end
