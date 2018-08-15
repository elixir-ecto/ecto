Code.require_file "../../../integration_test/support/types.exs", __DIR__

defmodule Ecto.Adapters.PostgresTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Ecto.Queryable
  alias Ecto.Adapters.Postgres.Connection, as: SQL

  defmodule Schema do
    use Ecto.Schema

    schema "schema" do
      field :x, :integer
      field :y, :integer
      field :z, :integer
      field :w, {:array, :integer}

      has_many :comments, Ecto.Adapters.PostgresTest.Schema2,
        references: :x,
        foreign_key: :z
      has_one :permalink, Ecto.Adapters.PostgresTest.Schema3,
        references: :y,
        foreign_key: :id
    end
  end

  defmodule Schema2 do
    use Ecto.Schema

    schema "schema2" do
      belongs_to :post, Ecto.Adapters.PostgresTest.Schema,
        references: :x,
        foreign_key: :z
    end
  end

  defmodule Schema3 do
    use Ecto.Schema

    schema "schema3" do
      field :list1, {:array, :string}
      field :list2, {:array, :integer}
      field :binary, :binary
    end
  end

  defp normalize(query, operation \\ :all, counter \\ 0) do
    {query, _params, _key} = Ecto.Query.Planner.prepare(query, operation, Ecto.Adapters.Postgres, counter)
    {query, _} = Ecto.Query.Planner.normalize(query, operation, Ecto.Adapters.Postgres, counter)
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
    query = Schema |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0}
  end

  test "from without schema" do
    query = "posts" |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT p0."x" FROM "posts" AS p0}

    query = "Posts" |> select([:x]) |> normalize
    assert all(query) == ~s{SELECT P0."x" FROM "Posts" AS P0}

    query = "0posts" |> select([:x]) |> normalize
    assert all(query) == ~s{SELECT t0."x" FROM "0posts" AS t0}

    assert_raise Ecto.QueryError, ~r"PostgreSQL does not support selecting all fields from \"posts\" without a schema", fn ->
      all from(p in "posts", select: p) |> normalize()
    end
  end

  test "from with subquery" do
    query = subquery("posts" |> select([r], %{x: r.x, y: r.y})) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM (SELECT p0."x" AS "x", p0."y" AS "y" FROM "posts" AS p0) AS s0}

    query = subquery("posts" |> select([r], %{x: r.x, z: r.y})) |> select([r], r) |> normalize
    assert all(query) == ~s{SELECT s0."x", s0."z" FROM (SELECT p0."x" AS "x", p0."y" AS "z" FROM "posts" AS p0) AS s0}
  end

  test "select" do
    query = Schema |> select([r], {r.x, r.y}) |> normalize
    assert all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> select([r], [r.x, r.y]) |> normalize
    assert all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> select([r], struct(r, [:x, :y])) |> normalize
    assert all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}
  end

  test "aggregates" do
    query = Schema |> select([r], count(r.x)) |> normalize
    assert all(query) == ~s{SELECT count(s0."x") FROM "schema" AS s0}

    query = Schema |> select([r], count(r.x, :distinct)) |> normalize
    assert all(query) == ~s{SELECT count(DISTINCT s0."x") FROM "schema" AS s0}
  end

  test "distinct" do
    query = Schema |> distinct([r], r.x) |> select([r], {r.x, r.y}) |> normalize
    assert all(query) == ~s{SELECT DISTINCT ON (s0."x") s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct([r], desc: r.x) |> select([r], {r.x, r.y}) |> normalize
    assert all(query) == ~s{SELECT DISTINCT ON (s0."x") s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct([r], 2) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT DISTINCT ON (2) s0."x" FROM "schema" AS s0}

    query = Schema |> distinct([r], [r.x, r.y]) |> select([r], {r.x, r.y}) |> normalize
    assert all(query) == ~s{SELECT DISTINCT ON (s0."x", s0."y") s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct([r], true) |> select([r], {r.x, r.y}) |> normalize
    assert all(query) == ~s{SELECT DISTINCT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct([r], false) |> select([r], {r.x, r.y}) |> normalize
    assert all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct(true) |> select([r], {r.x, r.y}) |> normalize
    assert all(query) == ~s{SELECT DISTINCT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct(false) |> select([r], {r.x, r.y}) |> normalize
    assert all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}
  end

  test "distinct with order by" do
    query = Schema |> order_by([r], [r.y]) |> distinct([r], desc: r.x) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT DISTINCT ON (s0."x") s0."x" FROM "schema" AS s0 ORDER BY s0."x" DESC, s0."y"}
  end

  test "where" do
    query = Schema |> where([r], r.x == 42) |> where([r], r.y != 43) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 WHERE (s0."x" = 42) AND (s0."y" != 43)}
  end

  test "or_where" do
    query = Schema |> or_where([r], r.x == 42) |> or_where([r], r.y != 43) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 WHERE (s0."x" = 42) OR (s0."y" != 43)}

    query = Schema |> or_where([r], r.x == 42) |> or_where([r], r.y != 43) |> where([r], r.z == 44) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 WHERE ((s0."x" = 42) OR (s0."y" != 43)) AND (s0."z" = 44)}
  end

  test "order by" do
    query = Schema |> order_by([r], r.x) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 ORDER BY s0."x"}

    query = Schema |> order_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 ORDER BY s0."x", s0."y"}

    query = Schema |> order_by([r], [asc: r.x, desc: r.y]) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 ORDER BY s0."x", s0."y" DESC}

    query = Schema |> order_by([r], []) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0}
  end

  test "limit and offset" do
    query = Schema |> limit([r], 3) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 LIMIT 3}

    query = Schema |> offset([r], 5) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 OFFSET 5}

    query = Schema |> offset([r], 5) |> limit([r], 3) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 LIMIT 3 OFFSET 5}
  end

  test "lock" do
    query = Schema |> lock("FOR SHARE NOWAIT") |> select([], true) |> normalize
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 FOR SHARE NOWAIT}
  end

  test "string escape" do
    query = "schema" |> where(foo: "'\\  ") |> select([], true) |> normalize
    assert all(query) == ~s{SELECT TRUE FROM \"schema\" AS s0 WHERE (s0.\"foo\" = '''\\  ')}

    query = "schema" |> where(foo: "'") |> select([], true) |> normalize
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 WHERE (s0."foo" = '''')}
  end

  test "binary ops" do
    query = Schema |> select([r], r.x == 2) |> normalize
    assert all(query) == ~s{SELECT s0."x" = 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x != 2) |> normalize
    assert all(query) == ~s{SELECT s0."x" != 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x <= 2) |> normalize
    assert all(query) == ~s{SELECT s0."x" <= 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x >= 2) |> normalize
    assert all(query) == ~s{SELECT s0."x" >= 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x < 2) |> normalize
    assert all(query) == ~s{SELECT s0."x" < 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x > 2) |> normalize
    assert all(query) == ~s{SELECT s0."x" > 2 FROM "schema" AS s0}
  end

  test "is_nil" do
    query = Schema |> select([r], is_nil(r.x)) |> normalize
    assert all(query) == ~s{SELECT s0."x" IS NULL FROM "schema" AS s0}

    query = Schema |> select([r], not is_nil(r.x)) |> normalize
    assert all(query) == ~s{SELECT NOT (s0."x" IS NULL) FROM "schema" AS s0}
  end

  test "fragments" do
    query = Schema |> select([r], fragment("now")) |> normalize
    assert all(query) == ~s{SELECT now FROM "schema" AS s0}

    query = Schema |> select([r], fragment("downcase(?)", r.x)) |> normalize
    assert all(query) == ~s{SELECT downcase(s0."x") FROM "schema" AS s0}

    value = 13
    query = Schema |> select([r], fragment("downcase(?, ?)", r.x, ^value)) |> normalize
    assert all(query) == ~s{SELECT downcase(s0."x", $1) FROM "schema" AS s0}

    query = Schema |> select([], fragment(title: 2)) |> normalize
    assert_raise Ecto.QueryError, fn ->
      all(query)
    end
  end

  test "literals" do
    query = "schema" |> where(foo: true) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 WHERE (s0."foo" = TRUE)}

    query = "schema" |> where(foo: false) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 WHERE (s0."foo" = FALSE)}

    query = "schema" |> where(foo: "abc") |> select([], true) |> normalize
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 WHERE (s0."foo" = 'abc')}

    query = "schema" |> where(foo: <<0,?a,?b,?c>>) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 WHERE (s0."foo" = '\\x00616263'::bytea)}

    query = "schema" |> where(foo: 123) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 WHERE (s0."foo" = 123)}

    query = "schema" |> where(foo: 123.0) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 WHERE (s0."foo" = 123.0::float)}
  end

  test "tagged type" do
    query = Schema |> select([], type(^"601d74e4-a8d3-4b6e-8365-eddb4c893327", Ecto.UUID)) |> normalize
    assert all(query) == ~s{SELECT $1::uuid FROM "schema" AS s0}

    query = Schema |> select([], type(^1, Custom.Permalink)) |> normalize
    assert all(query) == ~s{SELECT $1::bigint FROM "schema" AS s0}

    query = Schema |> select([], type(^[1,2,3], {:array, Custom.Permalink})) |> normalize
    assert all(query) == ~s{SELECT $1::bigint[] FROM "schema" AS s0}
  end

  test "nested expressions" do
    z = 123
    query = from(r in Schema, []) |> select([r], r.x > 0 and (r.y > ^(-z)) or true) |> normalize
    assert all(query) == ~s{SELECT ((s0."x" > 0) AND (s0."y" > $1)) OR TRUE FROM "schema" AS s0}
  end

  test "in expression" do
    query = Schema |> select([e], 1 in []) |> normalize
    assert all(query) == ~s{SELECT false FROM "schema" AS s0}

    query = Schema |> select([e], 1 in [1,e.x,3]) |> normalize
    assert all(query) == ~s{SELECT 1 IN (1,s0."x",3) FROM "schema" AS s0}

    query = Schema |> select([e], 1 in ^[]) |> normalize
    assert all(query) == ~s{SELECT 1 = ANY($1) FROM "schema" AS s0}

    query = Schema |> select([e], 1 in ^[1, 2, 3]) |> normalize
    assert all(query) == ~s{SELECT 1 = ANY($1) FROM "schema" AS s0}

    query = Schema |> select([e], 1 in [1, ^2, 3]) |> normalize
    assert all(query) == ~s{SELECT 1 IN (1,$1,3) FROM "schema" AS s0}

    query = Schema |> select([e], ^1 in [1, ^2, 3]) |> normalize
    assert all(query) == ~s{SELECT $1 IN (1,$2,3) FROM "schema" AS s0}

    query = Schema |> select([e], ^1 in ^[1, 2, 3]) |> normalize
    assert all(query) == ~s{SELECT $1 = ANY($2) FROM "schema" AS s0}

    query = Schema |> select([e], 1 in e.w) |> normalize
    assert all(query) == ~s{SELECT 1 = ANY(s0."w") FROM "schema" AS s0}

    query = Schema |> select([e], 1 in fragment("foo")) |> normalize
    assert all(query) == ~s{SELECT 1 = ANY(foo) FROM "schema" AS s0}

    query = Schema |> select([e], e.x == ^0 or e.x in ^[1, 2, 3] or e.x == ^4) |> normalize
    assert all(query) == ~s{SELECT ((s0."x" = $1) OR s0."x" = ANY($2)) OR (s0."x" = $3) FROM "schema" AS s0}
  end

  test "having" do
    query = Schema |> having([p], p.x == p.x) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 HAVING (s0."x" = s0."x")}

    query = Schema |> having([p], p.x == p.x) |> having([p], p.y == p.y) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 HAVING (s0."x" = s0."x") AND (s0."y" = s0."y")}
  end

  test "or_having" do
    query = Schema |> or_having([p], p.x == p.x) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 HAVING (s0."x" = s0."x")}

    query = Schema |> or_having([p], p.x == p.x) |> or_having([p], p.y == p.y) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 HAVING (s0."x" = s0."x") OR (s0."y" = s0."y")}
  end

  test "group by" do
    query = Schema |> group_by([r], r.x) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 GROUP BY s0."x"}

    query = Schema |> group_by([r], 2) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 GROUP BY 2}

    query = Schema |> group_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 GROUP BY s0."x", s0."y"}

    query = Schema |> group_by([r], []) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0}
  end

  test "arrays and sigils" do
    query = Schema |> select([], fragment("?", [1, 2, 3])) |> normalize
    assert all(query) == ~s{SELECT ARRAY[1,2,3] FROM "schema" AS s0}

    query = Schema |> select([], fragment("?", ~w(abc def))) |> normalize
    assert all(query) == ~s{SELECT ARRAY['abc','def'] FROM "schema" AS s0}
  end

  test "interpolated values" do
    query = "schema"
            |> select([m], {m.id, ^true})
            |> join(:inner, [], Schema2, fragment("?", ^true))
            |> join(:inner, [], Schema2, fragment("?", ^false))
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
      "SELECT s0.\"id\", $1 FROM \"schema\" AS s0 INNER JOIN \"schema2\" AS s1 ON $2 " <>
      "INNER JOIN \"schema2\" AS s2 ON $3 WHERE ($4) AND ($5) " <>
      "GROUP BY $6, $7 HAVING ($8) AND ($9) " <>
      "ORDER BY $10, s0.\"x\" LIMIT $11 OFFSET $12"

    assert all(query) == String.trim(result)
  end

  test "fragments and types" do
    query =
      normalize from(e in "schema",
        where: fragment("extract(? from ?) = ?", ^"month", e.start_time, type(^"4", :integer)),
        where: fragment("extract(? from ?) = ?", ^"year", e.start_time, type(^"2015", :integer)),
        select: true)

    result =
      "SELECT TRUE FROM \"schema\" AS s0 " <>
      "WHERE (extract($1 from s0.\"start_time\") = $2::bigint) " <>
      "AND (extract($3 from s0.\"start_time\") = $4::bigint)"

    assert all(query) == String.trim(result)
  end

  test "fragments allow ? to be escaped with backslash" do
    query =
      normalize  from(e in "schema",
        where: fragment("? = \"query\\?\"", e.start_time),
        select: true)

    result =
      "SELECT TRUE FROM \"schema\" AS s0 " <>
      "WHERE (s0.\"start_time\" = \"query?\")"

    assert all(query) == String.trim(result)
  end

  ## *_all

  test "update all" do
    query = from(m in Schema, update: [set: [x: 0]]) |> normalize(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "schema" AS s0 SET "x" = 0}

    query = from(m in Schema, update: [set: [x: 0], inc: [y: 1, z: -3]]) |> normalize(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "schema" AS s0 SET "x" = 0, "y" = s0."y" + 1, "z" = s0."z" + -3}

    query = from(e in Schema, where: e.x == 123, update: [set: [x: 0]]) |> normalize(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "schema" AS s0 SET "x" = 0 WHERE (s0."x" = 123)}

    query = from(m in Schema, update: [set: [x: ^0]]) |> normalize(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "schema" AS s0 SET "x" = $1}

    query = Schema |> join(:inner, [p], q in Schema2, p.x == q.z)
                  |> update([_], set: [x: 0]) |> normalize(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "schema" AS s0 SET "x" = 0 FROM "schema2" AS s1 WHERE (s0."x" = s1."z")}

    query = from(e in Schema, where: e.x == 123, update: [set: [x: 0]],
                             join: q in Schema2, on: e.x == q.z) |> normalize(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "schema" AS s0 SET "x" = 0 FROM "schema2" AS s1 } <>
           ~s{WHERE (s0."x" = s1."z") AND (s0."x" = 123)}
  end

  test "update all with returning" do
    query = from(m in Schema, update: [set: [x: 0]]) |> select([m], m) |> normalize(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "schema" AS s0 SET "x" = 0 RETURNING s0."id", s0."x", s0."y", s0."z", s0."w"}
  end

  test "update all array ops" do
    query = from(m in Schema, update: [push: [w: 0]]) |> normalize(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "schema" AS s0 SET "w" = array_append(s0."w", 0)}

    query = from(m in Schema, update: [pull: [w: 0]]) |> normalize(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "schema" AS s0 SET "w" = array_remove(s0."w", 0)}
  end

  test "update all with prefix" do
    query = from(m in Schema, update: [set: [x: 0]]) |> normalize(:update_all)
    assert update_all(%{query | prefix: "prefix"}) ==
           ~s{UPDATE "prefix"."schema" AS s0 SET "x" = 0}
  end

  test "delete all" do
    query = Schema |> Queryable.to_query |> normalize
    assert delete_all(query) == ~s{DELETE FROM "schema" AS s0}

    query = from(e in Schema, where: e.x == 123) |> normalize
    assert delete_all(query) ==
           ~s{DELETE FROM "schema" AS s0 WHERE (s0."x" = 123)}

    query = Schema |> join(:inner, [p], q in Schema2, p.x == q.z) |> normalize
    assert delete_all(query) ==
           ~s{DELETE FROM "schema" AS s0 USING "schema2" AS s1 WHERE (s0."x" = s1."z")}

    query = from(e in Schema, where: e.x == 123, join: q in Schema2, on: e.x == q.z) |> normalize
    assert delete_all(query) ==
           ~s{DELETE FROM "schema" AS s0 USING "schema2" AS s1 WHERE (s0."x" = s1."z") AND (s0."x" = 123)}

    query = from(e in Schema, where: e.x == 123, join: assoc(e, :comments), join: assoc(e, :permalink)) |> normalize
    assert delete_all(query) ==
           ~s{DELETE FROM "schema" AS s0 USING "schema2" AS s1, "schema3" AS s2 WHERE (s1."z" = s0."x") AND (s2."id" = s0."y") AND (s0."x" = 123)}
  end

  test "delete all with returning" do
    query = Schema |> Queryable.to_query |> select([m], m) |> normalize
    assert delete_all(query) == ~s{DELETE FROM "schema" AS s0 RETURNING s0."id", s0."x", s0."y", s0."z", s0."w"}
  end

  test "delete all with prefix" do
    query = Schema |> Queryable.to_query |> normalize
    assert delete_all(%{query | prefix: "prefix"}) == ~s{DELETE FROM "prefix"."schema" AS s0}
  end

  ## Joins

  test "join" do
    query = Schema |> join(:inner, [p], q in Schema2, p.x == q.z) |> select([], true) |> normalize
    assert all(query) ==
           ~s{SELECT TRUE FROM "schema" AS s0 INNER JOIN "schema2" AS s1 ON s0."x" = s1."z"}

    query = Schema |> join(:inner, [p], q in Schema2, p.x == q.z)
                  |> join(:inner, [], Schema, true) |> select([], true) |> normalize
    assert all(query) ==
           ~s{SELECT TRUE FROM "schema" AS s0 INNER JOIN "schema2" AS s1 ON s0."x" = s1."z" } <>
           ~s{INNER JOIN "schema" AS s2 ON TRUE}
  end

  test "join with nothing bound" do
    query = Schema |> join(:inner, [], q in Schema2, q.z == q.z) |> select([], true) |> normalize
    assert all(query) ==
           ~s{SELECT TRUE FROM "schema" AS s0 INNER JOIN "schema2" AS s1 ON s1."z" = s1."z"}
  end

  test "join without schema" do
    query = "posts" |> join(:inner, [p], q in "comments", p.x == q.z) |> select([], true) |> normalize
    assert all(query) ==
           ~s{SELECT TRUE FROM "posts" AS p0 INNER JOIN "comments" AS c1 ON p0."x" = c1."z"}
  end

  test "join with subquery" do
    posts = subquery("posts" |> where(title: ^"hello") |> select([r], %{x: r.x, y: r.y}))
    query = "comments" |> join(:inner, [c], p in subquery(posts), true) |> select([_, p], p.x) |> normalize
    assert all(query) ==
           ~s{SELECT s1."x" FROM "comments" AS c0 } <>
           ~s{INNER JOIN (SELECT p0."x" AS "x", p0."y" AS "y" FROM "posts" AS p0 WHERE (p0."title" = $1)) AS s1 ON TRUE}

    posts = subquery("posts" |> where(title: ^"hello") |> select([r], %{x: r.x, z: r.y}))
    query = "comments" |> join(:inner, [c], p in subquery(posts), true) |> select([_, p], p) |> normalize
    assert all(query) ==
           ~s{SELECT s1."x", s1."z" FROM "comments" AS c0 } <>
           ~s{INNER JOIN (SELECT p0."x" AS "x", p0."y" AS "z" FROM "posts" AS p0 WHERE (p0."title" = $1)) AS s1 ON TRUE}
  end

  test "join with prefix" do
    query = Schema |> join(:inner, [p], q in Schema2, p.x == q.z) |> select([], true) |> normalize
    assert all(%{query | prefix: "prefix"}) ==
           ~s{SELECT TRUE FROM "prefix"."schema" AS s0 INNER JOIN "prefix"."schema2" AS s1 ON s0."x" = s1."z"}
  end

  test "join with fragment" do
    query = Schema
            |> join(:inner, [p], q in fragment("SELECT * FROM schema2 AS s2 WHERE s2.id = ? AND s2.field = ?", p.x, ^10))
            |> select([p], {p.id, ^0})
            |> where([p], p.id > 0 and p.id < ^100)
            |> normalize
    assert all(query) ==
           ~s{SELECT s0."id", $1 FROM "schema" AS s0 INNER JOIN } <>
           ~s{(SELECT * FROM schema2 AS s2 WHERE s2.id = s0."x" AND s2.field = $2) AS f1 ON TRUE } <>
           ~s{WHERE ((s0."id" > 0) AND (s0."id" < $3))}
  end

  test "join with fragment and on defined" do
    query = Schema
            |> join(:inner, [p], q in fragment("SELECT * FROM schema2"), q.id == p.id)
            |> select([p], {p.id, ^0})
            |> normalize
    assert all(query) ==
           ~s{SELECT s0."id", $1 FROM "schema" AS s0 INNER JOIN } <>
           ~s{(SELECT * FROM schema2) AS f1 ON f1."id" = s0."id"}
  end

  test "join with query interpolation" do
    inner = Ecto.Queryable.to_query(Schema2)
    query = from(p in Schema, left_join: c in ^inner, select: {p.id, c.id}) |> normalize()
    assert all(query) ==
           "SELECT s0.\"id\", s1.\"id\" FROM \"schema\" AS s0 LEFT OUTER JOIN \"schema2\" AS s1 ON TRUE"
  end

  test "lateral join with fragment" do
    query = Schema
            |> join(:inner_lateral, [p], q in fragment("SELECT * FROM schema2 AS s2 WHERE s2.id = ? AND s2.field = ?", p.x, ^10))
            |> select([p, q], {p.id, q.z})
            |> where([p], p.id > 0 and p.id < ^100)
            |> normalize
    assert all(query) ==
           ~s{SELECT s0."id", f1."z" FROM "schema" AS s0 INNER JOIN LATERAL } <>
           ~s{(SELECT * FROM schema2 AS s2 WHERE s2.id = s0."x" AND s2.field = $1) AS f1 ON TRUE } <>
           ~s{WHERE ((s0."id" > 0) AND (s0."id" < $2))}
  end

  test "cross join" do
    query = from(p in Schema, cross_join: c in Schema2, select: {p.id, c.id}) |> normalize()
    assert all(query) ==
           "SELECT s0.\"id\", s1.\"id\" FROM \"schema\" AS s0 CROSS JOIN \"schema2\" AS s1"
  end

  test "join produces correct bindings" do
    query = from(p in Schema, join: c in Schema2, on: true)
    query = from(p in query, join: c in Schema2, on: true, select: {p.id, c.id})
    query = normalize(query)
    assert all(query) ==
           "SELECT s0.\"id\", s2.\"id\" FROM \"schema\" AS s0 INNER JOIN \"schema2\" AS s1 ON TRUE INNER JOIN \"schema2\" AS s2 ON TRUE"
  end

  describe "query interpolation parameters" do
    test "self join on subquery" do
      subquery = select(Schema, [r], %{x: r.x, y: r.y})
      query = subquery |> join(:inner, [c], p in subquery(subquery), true) |> normalize
      assert all(query) ==
             ~s{SELECT s0."x", s0."y" FROM "schema" AS s0 INNER JOIN } <>
             ~s{(SELECT s0."x" AS "x", s0."y" AS "y" FROM "schema" AS s0) } <>
             ~s{AS s1 ON TRUE}
    end

    test "self join on subquery with fragment" do
      subquery = select(Schema, [r], %{string: fragment("downcase(?)", ^"string")})
      query = subquery |> join(:inner, [c], p in subquery(subquery), true) |> normalize
      assert all(query) ==
             ~s{SELECT downcase($1) FROM "schema" AS s0 INNER JOIN } <>
             ~s{(SELECT downcase($2) AS "string" FROM "schema" AS s0) } <>
             ~s{AS s1 ON TRUE}
    end

    test "join on subquery with simple select" do
      subquery = select(Schema, [r], %{x: ^999, w: ^888})
      query = Schema
              |> select([r], %{y: ^666})
              |> join(:inner, [c], p in subquery(subquery), true)
              |> where([a, b], a.x == ^111)
              |> normalize

      assert all(query) ==
             ~s{SELECT $1 FROM "schema" AS s0 INNER JOIN } <>
             ~s{(SELECT $2 AS "x", $3 AS "w" FROM "schema" AS s0) AS s1 ON TRUE } <>
             ~s{WHERE (s0."x" = $4)}
    end
  end

  ## Associations

  test "association join belongs_to" do
    query = Schema2 |> join(:inner, [c], p in assoc(c, :post)) |> select([], true) |> normalize
    assert all(query) ==
           "SELECT TRUE FROM \"schema2\" AS s0 INNER JOIN \"schema\" AS s1 ON s1.\"x\" = s0.\"z\""
  end

  test "association join has_many" do
    query = Schema |> join(:inner, [p], c in assoc(p, :comments)) |> select([], true) |> normalize
    assert all(query) ==
           "SELECT TRUE FROM \"schema\" AS s0 INNER JOIN \"schema2\" AS s1 ON s1.\"z\" = s0.\"x\""
  end

  test "association join has_one" do
    query = Schema |> join(:inner, [p], pp in assoc(p, :permalink)) |> select([], true) |> normalize
    assert all(query) ==
           "SELECT TRUE FROM \"schema\" AS s0 INNER JOIN \"schema3\" AS s1 ON s1.\"id\" = s0.\"y\""
  end

  # Schema based

  test "insert" do
    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {:raise, [], []}, [:id])
    assert query == ~s{INSERT INTO "schema" ("x","y") VALUES ($1,$2) RETURNING "id"}

    query = insert(nil, "schema", [:x, :y], [[:x, :y], [nil, :z]], {:raise, [], []}, [:id])
    assert query == ~s{INSERT INTO "schema" ("x","y") VALUES ($1,$2),(DEFAULT,$3) RETURNING "id"}

    query = insert(nil, "schema", [], [[]], {:raise, [], []}, [:id])
    assert query == ~s{INSERT INTO "schema" VALUES (DEFAULT) RETURNING "id"}

    query = insert(nil, "schema", [], [[]], {:raise, [], []}, [])
    assert query == ~s{INSERT INTO "schema" VALUES (DEFAULT)}

    query = insert("prefix", "schema", [], [[]], {:raise, [], []}, [])
    assert query == ~s{INSERT INTO "prefix"."schema" VALUES (DEFAULT)}
  end

  test "insert with on conflict" do
    # For :nothing
    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {:nothing, [], []}, [])
    assert query == ~s{INSERT INTO "schema" ("x","y") VALUES ($1,$2) ON CONFLICT DO NOTHING}

    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {:nothing, [], [:x, :y]}, [])
    assert query == ~s{INSERT INTO "schema" ("x","y") VALUES ($1,$2) ON CONFLICT ("x","y") DO NOTHING}

    # For :update
    update = from("schema", update: [set: [z: "foo"]]) |> normalize(:update_all)
    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {update, [], [:x, :y]}, [:z])
    assert query == ~s{INSERT INTO "schema" AS s0 ("x","y") VALUES ($1,$2) ON CONFLICT ("x","y") DO UPDATE SET "z" = 'foo' RETURNING "z"}

    update = from("schema", update: [set: [z: ^"foo"]], where: [w: true]) |> normalize(:update_all, 2)
    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {update, [], [:x, :y]}, [:z])
    assert query == ~s{INSERT INTO "schema" AS s0 ("x","y") VALUES ($1,$2) ON CONFLICT ("x","y") DO UPDATE SET "z" = $3 WHERE (s0."w" = TRUE) RETURNING "z"}

    # For :replace_all
    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {:replace_all, [], [:id]}, [])
    assert query == ~s{INSERT INTO "schema" ("x","y") VALUES ($1,$2) ON CONFLICT ("id") DO UPDATE SET "x" = EXCLUDED."x","y" = EXCLUDED."y"}

    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {:replace_all, [], []}, [])
    assert query == ~s{INSERT INTO "schema" ("x","y") VALUES ($1,$2) ON CONFLICT DO UPDATE SET "x" = EXCLUDED."x","y" = EXCLUDED."y"}

    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {:replace_all, [], {:constraint, :foo}}, [])
    assert query == ~s{INSERT INTO "schema" ("x","y") VALUES ($1,$2) ON CONFLICT ON CONSTRAINT \"foo\" DO UPDATE SET "x" = EXCLUDED."x","y" = EXCLUDED."y"}
  end

  test "update" do
    query = update(nil, "schema", [:x, :y], [:id], [])
    assert query == ~s{UPDATE "schema" SET "x" = $1, "y" = $2 WHERE "id" = $3}

    query = update(nil, "schema", [:x, :y], [:id], [:z])
    assert query == ~s{UPDATE "schema" SET "x" = $1, "y" = $2 WHERE "id" = $3 RETURNING "z"}

    query = update("prefix", "schema", [:x, :y], [:id], [])
    assert query == ~s{UPDATE "prefix"."schema" SET "x" = $1, "y" = $2 WHERE "id" = $3}
  end

  test "delete" do
    query = delete(nil, "schema", [:x, :y], [])
    assert query == ~s{DELETE FROM "schema" WHERE "x" = $1 AND "y" = $2}

    query = delete(nil, "schema", [:x, :y], [:z])
    assert query == ~s{DELETE FROM "schema" WHERE "x" = $1 AND "y" = $2 RETURNING "z"}

    query = delete("prefix", "schema", [:x, :y], [])
    assert query == ~s{DELETE FROM "prefix"."schema" WHERE "x" = $1 AND "y" = $2}
  end

  # DDL

  alias Ecto.Migration.Reference
  import Ecto.Migration, only: [table: 1, table: 2, index: 2, index: 3,
                                constraint: 2, constraint: 3]

  test "executing a string during migration" do
    assert execute_ddl("example") == ["example"]
  end

  test "create table" do
    create = {:create, table(:posts),
              [{:add, :name, :string, [default: "Untitled", size: 20, null: false]},
               {:add, :price, :numeric, [precision: 8, scale: 2, default: {:fragment, "expr"}]},
               {:add, :on_hand, :integer, [default: 0, null: true]},
               {:add, :published_at, :"time without time zone", [null: true]},
               {:add, :is_active, :boolean, [default: true]},
               {:add, :tags, {:array, :string}, [default: []]}]}

    assert execute_ddl(create) == ["""
    CREATE TABLE "posts" ("name" varchar(20) DEFAULT 'Untitled' NOT NULL,
    "price" numeric(8,2) DEFAULT expr,
    "on_hand" integer DEFAULT 0 NULL,
    "published_at" time without time zone NULL,
    "is_active" boolean DEFAULT true,
    "tags" varchar(255)[] DEFAULT ARRAY[]::varchar[])
    """ |> remove_newlines]
  end

  test "create table with prefix" do
    create = {:create, table(:posts, prefix: :foo),
              [{:add, :category_0, %Reference{table: :categories}, []}]}

    assert execute_ddl(create) == ["""
    CREATE TABLE "foo"."posts"
    ("category_0" bigint CONSTRAINT "posts_category_0_fkey" REFERENCES "foo"."categories"("id"))
    """ |> remove_newlines]
  end

  test "create table with comment on columns and table" do
    create = {:create, table(:posts, comment: "comment"),
              [
                {:add, :category_0, %Reference{table: :categories}, [comment: "column comment"]},
                {:add, :created_at, :timestamp, []},
                {:add, :updated_at, :timestamp, [comment: "column comment 2"]}
              ]}
    assert execute_ddl(create) == [remove_newlines("""
    CREATE TABLE "posts"
    ("category_0" bigint CONSTRAINT "posts_category_0_fkey" REFERENCES "categories"("id"), "created_at" timestamp, "updated_at" timestamp)
    """),
    ~s|COMMENT ON TABLE "posts" IS 'comment'|,
    ~s|COMMENT ON COLUMN "posts"."category_0" IS 'column comment'|,
    ~s|COMMENT ON COLUMN "posts"."updated_at" IS 'column comment 2'|]
  end

  test "create table with comment on table" do
    create = {:create, table(:posts, comment: "table comment", prefix: "foo"),
              [{:add, :category_0, %Reference{table: :categories}, []}]}
    assert execute_ddl(create) == [remove_newlines("""
    CREATE TABLE "foo"."posts"
    ("category_0" bigint CONSTRAINT "posts_category_0_fkey" REFERENCES "foo"."categories"("id"))
    """),
    ~s|COMMENT ON TABLE "foo"."posts" IS 'table comment'|]
  end

  test "create table with comment on columns" do
    create = {:create, table(:posts, prefix: "foo"),
              [
                {:add, :category_0, %Reference{table: :categories}, [comment: "column comment"]},
                {:add, :created_at, :timestamp, []},
                {:add, :updated_at, :timestamp, [comment: "column comment 2"]}
              ]}
    assert execute_ddl(create) == [remove_newlines("""
    CREATE TABLE "foo"."posts"
    ("category_0" bigint CONSTRAINT "posts_category_0_fkey" REFERENCES "foo"."categories"("id"), "created_at" timestamp, "updated_at" timestamp)
    """),
    ~s|COMMENT ON COLUMN "foo"."posts"."category_0" IS 'column comment'|,
    ~s|COMMENT ON COLUMN "foo"."posts"."updated_at" IS 'column comment 2'|]
  end

  test "create table with references" do
    create = {:create, table(:posts),
              [{:add, :id, :serial, [primary_key: true]},
               {:add, :category_0, %Reference{table: :categories}, []},
               {:add, :category_1, %Reference{table: :categories, name: :foo_bar}, []},
               {:add, :category_2, %Reference{table: :categories, on_delete: :nothing}, []},
               {:add, :category_3, %Reference{table: :categories, on_delete: :delete_all}, [null: false]},
               {:add, :category_4, %Reference{table: :categories, on_delete: :nilify_all}, []},
               {:add, :category_5, %Reference{table: :categories, on_update: :nothing}, []},
               {:add, :category_6, %Reference{table: :categories, on_update: :update_all}, [null: false]},
               {:add, :category_7, %Reference{table: :categories, on_update: :nilify_all}, []},
               {:add, :category_8, %Reference{table: :categories, on_delete: :nilify_all, on_update: :update_all}, [null: false]},
               {:add, :category_9, %Reference{table: :categories, on_delete: :restrict}, []},
               {:add, :category_10, %Reference{table: :categories, on_update: :restrict}, []}]}

    assert execute_ddl(create) == ["""
    CREATE TABLE "posts" ("id" serial,
    "category_0" bigint CONSTRAINT "posts_category_0_fkey" REFERENCES "categories"("id"),
    "category_1" bigint CONSTRAINT "foo_bar" REFERENCES "categories"("id"),
    "category_2" bigint CONSTRAINT "posts_category_2_fkey" REFERENCES "categories"("id"),
    "category_3" bigint NOT NULL CONSTRAINT "posts_category_3_fkey" REFERENCES "categories"("id") ON DELETE CASCADE,
    "category_4" bigint CONSTRAINT "posts_category_4_fkey" REFERENCES "categories"("id") ON DELETE SET NULL,
    "category_5" bigint CONSTRAINT "posts_category_5_fkey" REFERENCES "categories"("id"),
    "category_6" bigint NOT NULL CONSTRAINT "posts_category_6_fkey" REFERENCES "categories"("id") ON UPDATE CASCADE,
    "category_7" bigint CONSTRAINT "posts_category_7_fkey" REFERENCES "categories"("id") ON UPDATE SET NULL,
    "category_8" bigint NOT NULL CONSTRAINT "posts_category_8_fkey" REFERENCES "categories"("id") ON DELETE SET NULL ON UPDATE CASCADE,
    "category_9" bigint CONSTRAINT "posts_category_9_fkey" REFERENCES "categories"("id") ON DELETE RESTRICT,
    "category_10" bigint CONSTRAINT "posts_category_10_fkey" REFERENCES "categories"("id") ON UPDATE RESTRICT,
    PRIMARY KEY ("id"))
    """ |> remove_newlines]
  end

  test "create table with options" do
    create = {:create, table(:posts, [options: "WITH FOO=BAR"]),
              [{:add, :id, :serial, [primary_key: true]},
               {:add, :created_at, :naive_datetime, []}]}
    assert execute_ddl(create) ==
      [~s|CREATE TABLE "posts" ("id" serial, "created_at" timestamp, PRIMARY KEY ("id")) WITH FOO=BAR|]
  end

  test "create table with composite key" do
    create = {:create, table(:posts),
              [{:add, :a, :integer, [primary_key: true]},
               {:add, :b, :integer, [primary_key: true]},
               {:add, :name, :string, []}]}

    assert execute_ddl(create) == ["""
    CREATE TABLE "posts" ("a" integer, "b" integer, "name" varchar(255), PRIMARY KEY ("a", "b"))
    """ |> remove_newlines]
  end

  test "create table with a map column, and an empty map default" do
    create = {:create, table(:posts),
              [
                {:add, :a, :map, [default: %{}]}
              ]
            }
    assert execute_ddl(create) == [~s|CREATE TABLE "posts" ("a" jsonb DEFAULT '{}')|]
  end

  test "create table with a map column, and a map default with values" do
    create = {:create, table(:posts),
              [
                {:add, :a, :map, [default: %{foo: "bar", baz: "boom"}]}
              ]
            }
    assert execute_ddl(create) == [~s|CREATE TABLE "posts" ("a" jsonb DEFAULT '{"foo":"bar","baz":"boom"}')|]
  end

  test "create table with a map column, and a string default" do
    create = {:create, table(:posts),
              [
                {:add, :a, :map, [default: ~s|{"foo":"bar","baz":"boom"}|]}
              ]
            }
    assert execute_ddl(create) == [~s|CREATE TABLE "posts" ("a" jsonb DEFAULT '{"foo":"bar","baz":"boom"}')|]
  end

  test "drop table" do
    drop = {:drop, table(:posts)}
    assert execute_ddl(drop) == [~s|DROP TABLE "posts"|]
  end

  test "drop table with prefix" do
    drop = {:drop, table(:posts, prefix: :foo)}
    assert execute_ddl(drop) == [~s|DROP TABLE "foo"."posts"|]
  end

  test "alter table" do
    alter = {:alter, table(:posts),
             [{:add, :title, :string, [default: "Untitled", size: 100, null: false]},
              {:add, :author_id, %Reference{table: :author}, []},
              {:modify, :price, :numeric, [precision: 8, scale: 2, null: true]},
              {:modify, :cost, :integer, [null: false, default: nil]},
              {:modify, :permalink_id, %Reference{table: :permalinks}, null: false},
              {:remove, :summary}]}

    assert execute_ddl(alter) == ["""
    ALTER TABLE "posts"
    ADD COLUMN "title" varchar(100) DEFAULT 'Untitled' NOT NULL,
    ADD COLUMN "author_id" bigint CONSTRAINT "posts_author_id_fkey" REFERENCES "author"("id"),
    ALTER COLUMN "price" TYPE numeric(8,2),
    ALTER COLUMN "price" DROP NOT NULL,
    ALTER COLUMN "cost" TYPE integer,
    ALTER COLUMN "cost" SET NOT NULL,
    ALTER COLUMN "cost" SET DEFAULT NULL,
    ALTER COLUMN "permalink_id" TYPE bigint,
    ADD CONSTRAINT "posts_permalink_id_fkey" FOREIGN KEY ("permalink_id") REFERENCES "permalinks"("id"),
    ALTER COLUMN "permalink_id" SET NOT NULL,
    DROP COLUMN "summary"
    """ |> remove_newlines]
  end

  test "alter table with comments on table and columns" do
    alter = {:alter, table(:posts, comment: "table comment"),
             [{:add, :title, :string, [default: "Untitled", size: 100, null: false, comment: "column comment"]},
              {:modify, :price, :numeric, [precision: 8, scale: 2, null: true]},
              {:modify, :permalink_id, %Reference{table: :permalinks}, [null: false, comment: "column comment"]},
              {:remove, :summary}]}

    assert execute_ddl(alter) == [remove_newlines("""
    ALTER TABLE "posts"
    ADD COLUMN "title" varchar(100) DEFAULT 'Untitled' NOT NULL,
    ALTER COLUMN "price" TYPE numeric(8,2),
    ALTER COLUMN "price" DROP NOT NULL,
    ALTER COLUMN "permalink_id" TYPE bigint,
    ADD CONSTRAINT "posts_permalink_id_fkey" FOREIGN KEY ("permalink_id") REFERENCES "permalinks"("id"),
    ALTER COLUMN "permalink_id" SET NOT NULL,
    DROP COLUMN "summary"
    """),
    ~s|COMMENT ON TABLE \"posts\" IS 'table comment'|,
    ~s|COMMENT ON COLUMN \"posts\".\"title\" IS 'column comment'|,
    ~s|COMMENT ON COLUMN \"posts\".\"permalink_id\" IS 'column comment'|]

  end

  test "alter table with prefix" do
    alter = {:alter, table(:posts, prefix: :foo),
             [{:add, :author_id, %Reference{table: :author}, []},
              {:modify, :permalink_id, %Reference{table: :permalinks}, null: false}]}

    assert execute_ddl(alter) == ["""
    ALTER TABLE "foo"."posts"
    ADD COLUMN "author_id" bigint CONSTRAINT "posts_author_id_fkey" REFERENCES "foo"."author"("id"),
    ALTER COLUMN \"permalink_id\" TYPE bigint,
    ADD CONSTRAINT "posts_permalink_id_fkey" FOREIGN KEY ("permalink_id") REFERENCES "foo"."permalinks"("id"),
    ALTER COLUMN "permalink_id" SET NOT NULL
    """ |> remove_newlines]
  end

  test "alter table with serial primary key" do
    alter = {:alter, table(:posts),
             [{:add, :my_pk, :serial, [primary_key: true]}]}

    assert execute_ddl(alter) == ["""
    ALTER TABLE "posts"
    ADD COLUMN "my_pk" serial,
    ADD PRIMARY KEY ("my_pk")
    """ |> remove_newlines]
  end

  test "alter table with bigserial primary key" do
    alter = {:alter, table(:posts),
             [{:add, :my_pk, :bigserial, [primary_key: true]}]}

    assert execute_ddl(alter) == ["""
    ALTER TABLE "posts"
    ADD COLUMN "my_pk" bigserial,
    ADD PRIMARY KEY ("my_pk")
    """ |> remove_newlines]
  end

  test "create index" do
    create = {:create, index(:posts, [:category_id, :permalink])}
    assert execute_ddl(create) ==
      [~s|CREATE INDEX "posts_category_id_permalink_index" ON "posts" ("category_id", "permalink")|]

    create = {:create, index(:posts, ["lower(permalink)"], name: "posts$main")}
    assert execute_ddl(create) ==
      [~s|CREATE INDEX "posts$main" ON "posts" (lower(permalink))|]
  end

  test "create index with prefix" do
    create = {:create, index(:posts, [:category_id, :permalink], prefix: :foo)}
    assert execute_ddl(create) ==
      [~s|CREATE INDEX "posts_category_id_permalink_index" ON "foo"."posts" ("category_id", "permalink")|]

    create = {:create, index(:posts, ["lower(permalink)"], name: "posts$main", prefix: :foo)}
    assert execute_ddl(create) ==
      [~s|CREATE INDEX "posts$main" ON "foo"."posts" (lower(permalink))|]
  end

  test "create index with comment" do
    create = {:create, index(:posts, [:category_id, :permalink], prefix: :foo, comment: "comment")}
    assert execute_ddl(create) == [remove_newlines("""
    CREATE INDEX "posts_category_id_permalink_index" ON "foo"."posts" ("category_id", "permalink")
    """),
    ~s|COMMENT ON INDEX "posts_category_id_permalink_index" IS 'comment'|]
  end

  test "create unique index" do
    create = {:create, index(:posts, [:permalink], unique: true)}
    assert execute_ddl(create) ==
      [~s|CREATE UNIQUE INDEX "posts_permalink_index" ON "posts" ("permalink")|]
  end

  test "create unique index with condition" do
    create = {:create, index(:posts, [:permalink], unique: true, where: "public IS TRUE")}
    assert execute_ddl(create) ==
      [~s|CREATE UNIQUE INDEX "posts_permalink_index" ON "posts" ("permalink") WHERE public IS TRUE|]

    create = {:create, index(:posts, [:permalink], unique: true, where: :public)}
    assert execute_ddl(create) ==
      [~s|CREATE UNIQUE INDEX "posts_permalink_index" ON "posts" ("permalink") WHERE public|]
  end

  test "create index concurrently" do
    create = {:create, index(:posts, [:permalink], concurrently: true)}
    assert execute_ddl(create) ==
      [~s|CREATE INDEX CONCURRENTLY "posts_permalink_index" ON "posts" ("permalink")|]
  end

  test "create unique index concurrently" do
    create = {:create, index(:posts, [:permalink], concurrently: true, unique: true)}
    assert execute_ddl(create) ==
      [~s|CREATE UNIQUE INDEX CONCURRENTLY "posts_permalink_index" ON "posts" ("permalink")|]
  end

  test "create an index using a different type" do
    create = {:create, index(:posts, [:permalink], using: :hash)}
    assert execute_ddl(create) ==
      [~s|CREATE INDEX "posts_permalink_index" ON "posts" USING hash ("permalink")|]
  end

  test "drop index" do
    drop = {:drop, index(:posts, [:id], name: "posts$main")}
    assert execute_ddl(drop) == [~s|DROP INDEX "posts$main"|]
  end

  test "drop index with prefix" do
    drop = {:drop, index(:posts, [:id], name: "posts$main", prefix: :foo)}
    assert execute_ddl(drop) == [~s|DROP INDEX "foo"."posts$main"|]
  end

  test "drop index concurrently" do
    drop = {:drop, index(:posts, [:id], name: "posts$main", concurrently: true)}
    assert execute_ddl(drop) == [~s|DROP INDEX CONCURRENTLY "posts$main"|]
  end

  test "create check constraint" do
    create = {:create, constraint(:products, "price_must_be_positive", check: "price > 0")}
    assert execute_ddl(create) ==
      [~s|ALTER TABLE "products" ADD CONSTRAINT "price_must_be_positive" CHECK (price > 0)|]

    create = {:create, constraint(:products, "price_must_be_positive", check: "price > 0", prefix: "foo")}
    assert execute_ddl(create) ==
      [~s|ALTER TABLE "foo"."products" ADD CONSTRAINT "price_must_be_positive" CHECK (price > 0)|]
  end

  test "create exclusion constraint" do
    create = {:create, constraint(:products, "price_must_be_positive", exclude: ~s|gist (int4range("from", "to", '[]') WITH &&)|)}
    assert execute_ddl(create) ==
      [~s|ALTER TABLE "products" ADD CONSTRAINT "price_must_be_positive" EXCLUDE USING gist (int4range("from", "to", '[]') WITH &&)|]
  end

  test "create constraint with comment" do
    create = {:create, constraint(:products, "price_must_be_positive", check: "price > 0", prefix: "foo", comment: "comment")}
    assert execute_ddl(create) == [remove_newlines("""
    ALTER TABLE "foo"."products" ADD CONSTRAINT "price_must_be_positive" CHECK (price > 0)
    """),
    ~s|COMMENT ON CONSTRAINT "price_must_be_positive" ON "foo"."products" IS 'comment'|]
  end

  test "drop constraint" do
    drop = {:drop, constraint(:products, "price_must_be_positive")}
    assert execute_ddl(drop) ==
      [~s|ALTER TABLE "products" DROP CONSTRAINT "price_must_be_positive"|]

    drop = {:drop, constraint(:products, "price_must_be_positive", prefix: "foo")}
    assert execute_ddl(drop) ==
      [~s|ALTER TABLE "foo"."products" DROP CONSTRAINT "price_must_be_positive"|]
  end

  test "rename table" do
    rename = {:rename, table(:posts), table(:new_posts)}
    assert execute_ddl(rename) == [~s|ALTER TABLE "posts" RENAME TO "new_posts"|]
  end

  test "rename table with prefix" do
    rename = {:rename, table(:posts, prefix: :foo), table(:new_posts, prefix: :foo)}
    assert execute_ddl(rename) == [~s|ALTER TABLE "foo"."posts" RENAME TO "new_posts"|]
  end

  test "rename column" do
    rename = {:rename, table(:posts), :given_name, :first_name}
    assert execute_ddl(rename) == [~s|ALTER TABLE "posts" RENAME "given_name" TO "first_name"|]
  end

  test "rename column in prefixed table" do
    rename = {:rename, table(:posts, prefix: :foo), :given_name, :first_name}
    assert execute_ddl(rename) == [~s|ALTER TABLE "foo"."posts" RENAME "given_name" TO "first_name"|]
  end

  defp remove_newlines(string) do
    string |> String.trim |> String.replace("\n", " ")
  end
end
