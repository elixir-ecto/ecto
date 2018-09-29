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

  defp plan(query, operation \\ :all) do
    {query, _params} = Ecto.Adapter.Queryable.plan_query(operation, Ecto.Adapters.Postgres, query)
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
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0}
  end

  test "from with hints" do
    assert_raise Ecto.QueryError, ~r/table hints are not supported by PostgreSQL/, fn ->
      Schema |> from(hints: "USE INDEX FOO") |> select([r], r.x) |> plan() |> all()
    end
  end

  test "from without schema" do
    query = "posts" |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT p0."x" FROM "posts" AS p0}

    query = "Posts" |> select([:x]) |> plan()
    assert all(query) == ~s{SELECT P0."x" FROM "Posts" AS P0}

    query = "0posts" |> select([:x]) |> plan()
    assert all(query) == ~s{SELECT t0."x" FROM "0posts" AS t0}
  end

  test "from with subquery" do
    query = subquery("posts" |> select([r], %{x: r.x, y: r.y})) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0."x" FROM (SELECT p0."x" AS "x", p0."y" AS "y" FROM "posts" AS p0) AS s0}

    query = subquery("posts" |> select([r], %{x: r.x, z: r.y})) |> select([r], r) |> plan()
    assert all(query) == ~s{SELECT s0."x", s0."z" FROM (SELECT p0."x" AS "x", p0."y" AS "z" FROM "posts" AS p0) AS s0}
  end

  test "select" do
    query = Schema |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> select([r], [r.x, r.y]) |> plan()
    assert all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> select([r], struct(r, [:x, :y])) |> plan()
    assert all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}
  end

  test "aggregates" do
    query = Schema |> select([r], count(r.x)) |> plan()
    assert all(query) == ~s{SELECT count(s0."x") FROM "schema" AS s0}

    query = Schema |> select([r], count(r.x, :distinct)) |> plan()
    assert all(query) == ~s{SELECT count(DISTINCT s0."x") FROM "schema" AS s0}

    query = Schema |> select([r], count()) |> plan()
    assert all(query) == ~s{SELECT count(*) FROM "schema" AS s0}
  end

  test "aggregate filters" do
    query = Schema |> select([r], count(r.x) |> filter(r.x > 10)) |> plan()
    assert all(query) == ~s{SELECT count(s0."x") FILTER (WHERE s0."x" > 10) FROM "schema" AS s0}

    query = Schema |> select([r], count(r.x) |> filter(r.x > 10 and r.x < 50)) |> plan()
    assert all(query) == ~s{SELECT count(s0."x") FILTER (WHERE (s0."x" > 10) AND (s0."x" < 50)) FROM "schema" AS s0}

    query = Schema |> select([r], count() |> filter(r.x > 10)) |> plan()
    assert all(query) == ~s{SELECT count(*) FILTER (WHERE s0."x" > 10) FROM "schema" AS s0}
  end

  test "distinct" do
    query = Schema |> distinct([r], r.x) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT DISTINCT ON (s0."x") s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct([r], desc: r.x) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT DISTINCT ON (s0."x") s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct([r], 2) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT DISTINCT ON (2) s0."x" FROM "schema" AS s0}

    query = Schema |> distinct([r], [r.x, r.y]) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT DISTINCT ON (s0."x", s0."y") s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct([r], [asc: r.x, desc: r.y]) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT DISTINCT ON (s0."x", s0."y") s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct([r], [asc_nulls_first: r.x, desc_nulls_last: r.y]) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT DISTINCT ON (s0."x", s0."y") s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct([r], true) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT DISTINCT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct([r], false) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct(true) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT DISTINCT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct(false) |> select([r], {r.x, r.y}) |> plan()
    assert all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}
  end

  test "distinct with order by" do
    query = Schema |> order_by([r], [r.y]) |> distinct([r], desc: r.x) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT DISTINCT ON (s0."x") s0."x" FROM "schema" AS s0 ORDER BY s0."x" DESC, s0."y"}

    query = Schema |> order_by([r], [r.y]) |> distinct([r], desc_nulls_last: r.x) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT DISTINCT ON (s0."x") s0."x" FROM "schema" AS s0 ORDER BY s0."x" DESC NULLS LAST, s0."y"}
  end

  test "coalesce" do
    query = Schema |> select([s], coalesce(s.x, 5)) |> plan()
    assert all(query) == ~s{SELECT coalesce(s0."x", 5) FROM "schema" AS s0}
  end

  test "where" do
    query = Schema |> where([r], r.x == 42) |> where([r], r.y != 43) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 WHERE (s0."x" = 42) AND (s0."y" != 43)}

    query = Schema |> where([r], {r.x, r.y} > {1, 2}) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 WHERE ((s0."x",s0."y") > (1,2))}
  end

  test "or_where" do
    query = Schema |> or_where([r], r.x == 42) |> or_where([r], r.y != 43) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 WHERE (s0."x" = 42) OR (s0."y" != 43)}

    query = Schema |> or_where([r], r.x == 42) |> or_where([r], r.y != 43) |> where([r], r.z == 44) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 WHERE ((s0."x" = 42) OR (s0."y" != 43)) AND (s0."z" = 44)}
  end

  test "order by" do
    query = Schema |> order_by([r], r.x) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 ORDER BY s0."x"}

    query = Schema |> order_by([r], [r.x, r.y]) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 ORDER BY s0."x", s0."y"}

    query = Schema |> order_by([r], [asc: r.x, desc: r.y]) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 ORDER BY s0."x", s0."y" DESC}

    query = Schema |> order_by([r], [asc_nulls_first: r.x, desc_nulls_first: r.y]) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 ORDER BY s0."x" ASC NULLS FIRST, s0."y" DESC NULLS FIRST}

    query = Schema |> order_by([r], [asc_nulls_last: r.x, desc_nulls_last: r.y]) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 ORDER BY s0."x" ASC NULLS LAST, s0."y" DESC NULLS LAST}

    query = Schema |> order_by([r], []) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0}
  end

  test "union and union all" do
    base_query = Schema |> select([r], r.x) |> order_by([r], r.x) |> offset(10) |> limit(5)
    union_query1 = Schema |> select([r], r.y) |> order_by([r], r.y) |> offset(20) |> limit(40)
    union_query2 = Schema |> select([r], r.z) |> order_by([r], r.z) |> offset(30) |> limit(60)

    query = base_query |> union(union_query1) |> union(union_query2) |> plan()

    assert all(query) ==
             ~s{SELECT s0."x" FROM "schema" AS s0 } <>
               ~s{UNION (SELECT s0."y" FROM "schema" AS s0 ORDER BY s0."y" LIMIT 40 OFFSET 20) } <>
               ~s{UNION (SELECT s0."z" FROM "schema" AS s0 ORDER BY s0."z" LIMIT 60 OFFSET 30) } <>
               ~s{ORDER BY s0."x" LIMIT 5 OFFSET 10}

    query = base_query |> union_all(union_query1) |> union_all(union_query2) |> plan()

    assert all(query) ==
             ~s{SELECT s0."x" FROM "schema" AS s0 } <>
               ~s{UNION ALL (SELECT s0."y" FROM "schema" AS s0 ORDER BY s0."y" LIMIT 40 OFFSET 20) } <>
               ~s{UNION ALL (SELECT s0."z" FROM "schema" AS s0 ORDER BY s0."z" LIMIT 60 OFFSET 30) } <>
               ~s{ORDER BY s0."x" LIMIT 5 OFFSET 10}
  end

  test "except and except all" do
    base_query = Schema |> select([r], r.x) |> order_by([r], r.x) |> offset(10) |> limit(5)
    except_query1 = Schema |> select([r], r.y) |> order_by([r], r.y) |> offset(20) |> limit(40)
    except_query2 = Schema |> select([r], r.z) |> order_by([r], r.z) |> offset(30) |> limit(60)

    query = base_query |> except(except_query1) |> except(except_query2) |> plan()

    assert all(query) ==
             ~s{SELECT s0."x" FROM "schema" AS s0 } <>
               ~s{EXCEPT (SELECT s0."y" FROM "schema" AS s0 ORDER BY s0."y" LIMIT 40 OFFSET 20) } <>
               ~s{EXCEPT (SELECT s0."z" FROM "schema" AS s0 ORDER BY s0."z" LIMIT 60 OFFSET 30) } <>
               ~s{ORDER BY s0."x" LIMIT 5 OFFSET 10}

    query = base_query |> except_all(except_query1) |> except_all(except_query2) |> plan()

    assert all(query) ==
             ~s{SELECT s0."x" FROM "schema" AS s0 } <>
               ~s{EXCEPT ALL (SELECT s0."y" FROM "schema" AS s0 ORDER BY s0."y" LIMIT 40 OFFSET 20) } <>
               ~s{EXCEPT ALL (SELECT s0."z" FROM "schema" AS s0 ORDER BY s0."z" LIMIT 60 OFFSET 30) } <>
               ~s{ORDER BY s0."x" LIMIT 5 OFFSET 10}
  end

  test "intersect and intersect all" do
    base_query = Schema |> select([r], r.x) |> order_by([r], r.x) |> offset(10) |> limit(5)
    intersect_query1 = Schema |> select([r], r.y) |> order_by([r], r.y) |> offset(20) |> limit(40)
    intersect_query2 = Schema |> select([r], r.z) |> order_by([r], r.z) |> offset(30) |> limit(60)

    query = base_query |> intersect(intersect_query1) |> intersect(intersect_query2) |> plan()

    assert all(query) ==
             ~s{SELECT s0."x" FROM "schema" AS s0 } <>
               ~s{INTERSECT (SELECT s0."y" FROM "schema" AS s0 ORDER BY s0."y" LIMIT 40 OFFSET 20) } <>
               ~s{INTERSECT (SELECT s0."z" FROM "schema" AS s0 ORDER BY s0."z" LIMIT 60 OFFSET 30) } <>
               ~s{ORDER BY s0."x" LIMIT 5 OFFSET 10}

    query =
      base_query |> intersect_all(intersect_query1) |> intersect_all(intersect_query2) |> plan()

    assert all(query) ==
             ~s{SELECT s0."x" FROM "schema" AS s0 } <>
               ~s{INTERSECT ALL (SELECT s0."y" FROM "schema" AS s0 ORDER BY s0."y" LIMIT 40 OFFSET 20) } <>
               ~s{INTERSECT ALL (SELECT s0."z" FROM "schema" AS s0 ORDER BY s0."z" LIMIT 60 OFFSET 30) } <>
               ~s{ORDER BY s0."x" LIMIT 5 OFFSET 10}
  end

  test "limit and offset" do
    query = Schema |> limit([r], 3) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 LIMIT 3}

    query = Schema |> offset([r], 5) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 OFFSET 5}

    query = Schema |> offset([r], 5) |> limit([r], 3) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 LIMIT 3 OFFSET 5}
  end

  test "lock" do
    query = Schema |> lock("FOR SHARE NOWAIT") |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 FOR SHARE NOWAIT}
  end

  test "string escape" do
    query = "schema" |> where(foo: "'\\  ") |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM \"schema\" AS s0 WHERE (s0.\"foo\" = '''\\  ')}

    query = "schema" |> where(foo: "'") |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 WHERE (s0."foo" = '''')}
  end

  test "binary ops" do
    query = Schema |> select([r], r.x == 2) |> plan()
    assert all(query) == ~s{SELECT s0."x" = 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x != 2) |> plan()
    assert all(query) == ~s{SELECT s0."x" != 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x <= 2) |> plan()
    assert all(query) == ~s{SELECT s0."x" <= 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x >= 2) |> plan()
    assert all(query) == ~s{SELECT s0."x" >= 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x < 2) |> plan()
    assert all(query) == ~s{SELECT s0."x" < 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x > 2) |> plan()
    assert all(query) == ~s{SELECT s0."x" > 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x + 2) |> plan()
    assert all(query) == ~s{SELECT s0."x" + 2 FROM "schema" AS s0}
  end

  test "is_nil" do
    query = Schema |> select([r], is_nil(r.x)) |> plan()
    assert all(query) == ~s{SELECT s0."x" IS NULL FROM "schema" AS s0}

    query = Schema |> select([r], not is_nil(r.x)) |> plan()
    assert all(query) == ~s{SELECT NOT (s0."x" IS NULL) FROM "schema" AS s0}
  end

  test "fragments" do
    query = Schema |> select([r], fragment("now")) |> plan()
    assert all(query) == ~s{SELECT now FROM "schema" AS s0}

    query = Schema |> select([r], fragment("fun(?)", r)) |> plan()
    assert all(query) == ~s{SELECT fun(s0) FROM "schema" AS s0}

    query = Schema |> select([r], fragment("downcase(?)", r.x)) |> plan()
    assert all(query) == ~s{SELECT downcase(s0."x") FROM "schema" AS s0}

    value = 13
    query = Schema |> select([r], fragment("downcase(?, ?)", r.x, ^value)) |> plan()
    assert all(query) == ~s{SELECT downcase(s0."x", $1) FROM "schema" AS s0}

    query = Schema |> select([], fragment(title: 2)) |> plan()
    assert_raise Ecto.QueryError, fn ->
      all(query)
    end
  end

  test "literals" do
    query = "schema" |> where(foo: true) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 WHERE (s0."foo" = TRUE)}

    query = "schema" |> where(foo: false) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 WHERE (s0."foo" = FALSE)}

    query = "schema" |> where(foo: "abc") |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 WHERE (s0."foo" = 'abc')}

    query = "schema" |> where(foo: <<0,?a,?b,?c>>) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 WHERE (s0."foo" = '\\x00616263'::bytea)}

    query = "schema" |> where(foo: 123) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 WHERE (s0."foo" = 123)}

    query = "schema" |> where(foo: 123.0) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 WHERE (s0."foo" = 123.0::float)}
  end

  test "tagged type" do
    query = Schema |> select([], type(^"601d74e4-a8d3-4b6e-8365-eddb4c893327", Ecto.UUID)) |> plan()
    assert all(query) == ~s{SELECT $1::uuid FROM "schema" AS s0}

    query = Schema |> select([], type(^1, Custom.Permalink)) |> plan()
    assert all(query) == ~s{SELECT $1::bigint FROM "schema" AS s0}

    query = Schema |> select([], type(^[1,2,3], {:array, Custom.Permalink})) |> plan()
    assert all(query) == ~s{SELECT $1::bigint[] FROM "schema" AS s0}
  end

  test "nested expressions" do
    z = 123
    query = from(r in Schema, []) |> select([r], r.x > 0 and (r.y > ^(-z)) or true) |> plan()
    assert all(query) == ~s{SELECT ((s0."x" > 0) AND (s0."y" > $1)) OR TRUE FROM "schema" AS s0}
  end

  test "in expression" do
    query = Schema |> select([e], 1 in []) |> plan()
    assert all(query) == ~s{SELECT false FROM "schema" AS s0}

    query = Schema |> select([e], 1 in [1,e.x,3]) |> plan()
    assert all(query) == ~s{SELECT 1 IN (1,s0."x",3) FROM "schema" AS s0}

    query = Schema |> select([e], 1 in ^[]) |> plan()
    assert all(query) == ~s{SELECT 1 = ANY($1) FROM "schema" AS s0}

    query = Schema |> select([e], 1 in ^[1, 2, 3]) |> plan()
    assert all(query) == ~s{SELECT 1 = ANY($1) FROM "schema" AS s0}

    query = Schema |> select([e], 1 in [1, ^2, 3]) |> plan()
    assert all(query) == ~s{SELECT 1 IN (1,$1,3) FROM "schema" AS s0}

    query = Schema |> select([e], ^1 in [1, ^2, 3]) |> plan()
    assert all(query) == ~s{SELECT $1 IN (1,$2,3) FROM "schema" AS s0}

    query = Schema |> select([e], ^1 in ^[1, 2, 3]) |> plan()
    assert all(query) == ~s{SELECT $1 = ANY($2) FROM "schema" AS s0}

    query = Schema |> select([e], 1 in e.w) |> plan()
    assert all(query) == ~s{SELECT 1 = ANY(s0."w") FROM "schema" AS s0}

    query = Schema |> select([e], 1 in fragment("foo")) |> plan()
    assert all(query) == ~s{SELECT 1 = ANY(foo) FROM "schema" AS s0}

    query = Schema |> select([e], e.x == ^0 or e.x in ^[1, 2, 3] or e.x == ^4) |> plan()
    assert all(query) == ~s{SELECT ((s0."x" = $1) OR s0."x" = ANY($2)) OR (s0."x" = $3) FROM "schema" AS s0}
  end

  test "having" do
    query = Schema |> having([p], p.x == p.x) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 HAVING (s0."x" = s0."x")}

    query = Schema |> having([p], p.x == p.x) |> having([p], p.y == p.y) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 HAVING (s0."x" = s0."x") AND (s0."y" = s0."y")}
  end

  test "or_having" do
    query = Schema |> or_having([p], p.x == p.x) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 HAVING (s0."x" = s0."x")}

    query = Schema |> or_having([p], p.x == p.x) |> or_having([p], p.y == p.y) |> select([], true) |> plan()
    assert all(query) == ~s{SELECT TRUE FROM "schema" AS s0 HAVING (s0."x" = s0."x") OR (s0."y" = s0."y")}
  end

  test "group by" do
    query = Schema |> group_by([r], r.x) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 GROUP BY s0."x"}

    query = Schema |> group_by([r], 2) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 GROUP BY 2}

    query = Schema |> group_by([r], [r.x, r.y]) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 GROUP BY s0."x", s0."y"}

    query = Schema |> group_by([r], []) |> select([r], r.x) |> plan()
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0}
  end

  test "arrays and sigils" do
    query = Schema |> select([], fragment("?", [1, 2, 3])) |> plan()
    assert all(query) == ~s{SELECT ARRAY[1,2,3] FROM "schema" AS s0}

    query = Schema |> select([], fragment("?", ~w(abc def))) |> plan()
    assert all(query) == ~s{SELECT ARRAY['abc','def'] FROM "schema" AS s0}
  end

  test "interpolated values" do
    query = "schema"
            |> select([m], {m.id, ^true})
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
      "SELECT s0.\"id\", $1 FROM \"schema\" AS s0 INNER JOIN \"schema2\" AS s1 ON $2 " <>
      "INNER JOIN \"schema2\" AS s2 ON $3 WHERE ($4) AND ($5) " <>
      "GROUP BY $6, $7 HAVING ($8) AND ($9) " <>
      "UNION (SELECT s0.\"id\", $10 FROM \"schema1\" AS s0 WHERE ($11)) " <>
      "UNION ALL (SELECT s0.\"id\", $12 FROM \"schema2\" AS s0 WHERE ($13)) " <>
      "ORDER BY $14, s0.\"x\" LIMIT $15 OFFSET $16"

    assert all(query) == String.trim(result)
  end

  test "order_by and types" do
    query = "schema3" |> order_by([e], type(fragment("?", e.binary), ^:decimal)) |> select(true) |> plan()
    assert all(query) == "SELECT TRUE FROM \"schema3\" AS s0 ORDER BY s0.\"binary\"::decimal"
  end

  test "fragments and types" do
    query =
      plan from(e in "schema",
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
      plan  from(e in "schema",
        where: fragment("? = \"query\\?\"", e.start_time),
        select: true)

    result =
      "SELECT TRUE FROM \"schema\" AS s0 " <>
      "WHERE (s0.\"start_time\" = \"query?\")"

    assert all(query) == String.trim(result)
  end

  ## *_all

  test "update all" do
    query = from(m in Schema, update: [set: [x: 0]]) |> plan(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "schema" AS s0 SET "x" = 0}

    query = from(m in Schema, update: [set: [x: 0], inc: [y: 1, z: -3]]) |> plan(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "schema" AS s0 SET "x" = 0, "y" = s0."y" + 1, "z" = s0."z" + -3}

    query = from(e in Schema, where: e.x == 123, update: [set: [x: 0]]) |> plan(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "schema" AS s0 SET "x" = 0 WHERE (s0."x" = 123)}

    query = from(m in Schema, update: [set: [x: ^0]]) |> plan(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "schema" AS s0 SET "x" = $1}

    query = Schema |> join(:inner, [p], q in Schema2, on: p.x == q.z)
                  |> update([_], set: [x: 0]) |> plan(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "schema" AS s0 SET "x" = 0 FROM "schema2" AS s1 WHERE (s0."x" = s1."z")}

    query = from(e in Schema, where: e.x == 123, update: [set: [x: 0]],
                             join: q in Schema2, on: e.x == q.z) |> plan(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "schema" AS s0 SET "x" = 0 FROM "schema2" AS s1 } <>
           ~s{WHERE (s0."x" = s1."z") AND (s0."x" = 123)}
  end

  test "update all with returning" do
    query = from(m in Schema, update: [set: [x: 0]]) |> select([m], m) |> plan(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "schema" AS s0 SET "x" = 0 RETURNING s0."id", s0."x", s0."y", s0."z", s0."w"}
  end

  test "update all array ops" do
    query = from(m in Schema, update: [push: [w: 0]]) |> plan(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "schema" AS s0 SET "w" = array_append(s0."w", 0)}

    query = from(m in Schema, update: [pull: [w: 0]]) |> plan(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "schema" AS s0 SET "w" = array_remove(s0."w", 0)}
  end

  test "update all with prefix" do
    query = from(m in Schema, update: [set: [x: 0]]) |> Map.put(:prefix, "prefix") |> plan(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "prefix"."schema" AS s0 SET "x" = 0}

    query = from(m in Schema, prefix: "first", update: [set: [x: 0]]) |> Map.put(:prefix, "prefix") |> plan(:update_all)
    assert update_all(query) ==
           ~s{UPDATE "first"."schema" AS s0 SET "x" = 0}
  end

  test "delete all" do
    query = Schema |> Queryable.to_query |> plan()
    assert delete_all(query) == ~s{DELETE FROM "schema" AS s0}

    query = from(e in Schema, where: e.x == 123) |> plan()
    assert delete_all(query) ==
           ~s{DELETE FROM "schema" AS s0 WHERE (s0."x" = 123)}

    query = Schema |> join(:inner, [p], q in Schema2, on: p.x == q.z) |> plan()
    assert delete_all(query) ==
           ~s{DELETE FROM "schema" AS s0 USING "schema2" AS s1 WHERE (s0."x" = s1."z")}

    query = from(e in Schema, where: e.x == 123, join: q in Schema2, on: e.x == q.z) |> plan()
    assert delete_all(query) ==
           ~s{DELETE FROM "schema" AS s0 USING "schema2" AS s1 WHERE (s0."x" = s1."z") AND (s0."x" = 123)}

    query = from(e in Schema, where: e.x == 123, join: assoc(e, :comments), join: assoc(e, :permalink)) |> plan()
    assert delete_all(query) ==
           ~s{DELETE FROM "schema" AS s0 USING "schema2" AS s1, "schema3" AS s2 WHERE (s1."z" = s0."x") AND (s2."id" = s0."y") AND (s0."x" = 123)}
  end

  test "delete all with returning" do
    query = Schema |> Queryable.to_query |> select([m], m) |> plan()
    assert delete_all(query) == ~s{DELETE FROM "schema" AS s0 RETURNING s0."id", s0."x", s0."y", s0."z", s0."w"}
  end

  test "delete all with prefix" do
    query = Schema |> Queryable.to_query |> Map.put(:prefix, "prefix") |> plan()
    assert delete_all(query) == ~s{DELETE FROM "prefix"."schema" AS s0}

    query = Schema |> from(prefix: "first") |> Map.put(:prefix, "prefix") |> plan()
    assert delete_all(query) == ~s{DELETE FROM "first"."schema" AS s0}
  end

  ## Partitions and windows

  describe "windows and partitions" do
    test "one window" do
      query = Schema
              |> select([r], r.x)
              |> windows([r], w: [partition_by: r.x])
              |> plan

      assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 WINDOW "w" AS (PARTITION BY s0."x")}
    end

    test "two windows" do
      query = Schema
              |> select([r], r.x)
              |> windows([r], w1: [partition_by: r.x], w2: [partition_by: r.y])
              |> plan()
      assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 WINDOW "w1" AS (PARTITION BY s0."x"), "w2" AS (PARTITION BY s0."y")}
    end

    test "count over window" do
      query = Schema
              |> windows([r], w: [partition_by: r.x])
              |> select([r], count(r.x) |> over(:w))
              |> plan()
      assert all(query) == ~s{SELECT count(s0."x") OVER "w" FROM "schema" AS s0 WINDOW "w" AS (PARTITION BY s0."x")}
    end

    test "count over all" do
      query = Schema
              |> select([r], count(r.x) |> over)
              |> plan()
      assert all(query) == ~s{SELECT count(s0."x") OVER () FROM "schema" AS s0}
    end

    test "row_number over all" do
      query = Schema
              |> select(row_number |> over)
              |> plan()
      assert all(query) == ~s{SELECT row_number() OVER () FROM "schema" AS s0}
    end

    test "nth_value over all" do
      query = Schema
              |> select([r], nth_value(r.x, 42) |> over)
              |> plan()
      assert all(query) == ~s{SELECT nth_value(s0."x", 42) OVER () FROM "schema" AS s0}
    end

    test "lag/2 over all" do
      query = Schema
              |> select([r], lag(r.x, 42) |> over)
              |> plan()
      assert all(query) == ~s{SELECT lag(s0."x", 42) OVER () FROM "schema" AS s0}
    end

    test "custom aggregation over all" do
      query = Schema
              |> select([r], fragment("custom_function(?)", r.x) |> over)
              |> plan()
      assert all(query) == ~s{SELECT custom_function(s0."x") OVER () FROM "schema" AS s0}
    end

    test "partition by and order by on window" do
      query = Schema
              |> windows([r], w: [partition_by: [r.x, r.z], order_by: r.x])
              |> select([r], r.x)
              |> plan()
      assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 WINDOW "w" AS (PARTITION BY s0."x", s0."z" ORDER BY s0."x")}
    end

    test "partition by ond order by over" do
      query = Schema
              |> select([r], count(r.x) |> over(partition_by: [r.x, r.z], order_by: r.x))

      query = query |> plan()
      assert all(query) == ~s{SELECT count(s0."x") OVER (PARTITION BY s0."x", s0."z" ORDER BY s0."x") FROM "schema" AS s0}
    end
  end

  ## Joins

  test "join" do
    query = Schema |> join(:inner, [p], q in Schema2, on: p.x == q.z) |> select([], true) |> plan()
    assert all(query) ==
           ~s{SELECT TRUE FROM "schema" AS s0 INNER JOIN "schema2" AS s1 ON s0."x" = s1."z"}

    query = Schema |> join(:inner, [p], q in Schema2, on: p.x == q.z)
                  |> join(:inner, [], Schema, on: true) |> select([], true) |> plan()
    assert all(query) ==
           ~s{SELECT TRUE FROM "schema" AS s0 INNER JOIN "schema2" AS s1 ON s0."x" = s1."z" } <>
           ~s{INNER JOIN "schema" AS s2 ON TRUE}
  end

  test "join with hints" do
    assert_raise Ecto.QueryError, ~r/table hints are not supported by PostgreSQL/, fn ->
      Schema
      |> join(:inner, [p], q in Schema2, hints: ["USE INDEX FOO", "USE INDEX BAR"])
      |> select([], true)
      |> plan()
      |> all()
    end
  end

  test "join with nothing bound" do
    query = Schema |> join(:inner, [], q in Schema2, on: q.z == q.z) |> select([], true) |> plan()
    assert all(query) ==
           ~s{SELECT TRUE FROM "schema" AS s0 INNER JOIN "schema2" AS s1 ON s1."z" = s1."z"}
  end

  test "join without schema" do
    query = "posts" |> join(:inner, [p], q in "comments", on: p.x == q.z) |> select([], true) |> plan()
    assert all(query) ==
           ~s{SELECT TRUE FROM "posts" AS p0 INNER JOIN "comments" AS c1 ON p0."x" = c1."z"}
  end

  test "join with subquery" do
    posts = subquery("posts" |> where(title: ^"hello") |> select([r], %{x: r.x, y: r.y}))
    query = "comments" |> join(:inner, [c], p in subquery(posts), on: true) |> select([_, p], p.x) |> plan()
    assert all(query) ==
           ~s{SELECT s1."x" FROM "comments" AS c0 } <>
           ~s{INNER JOIN (SELECT p0."x" AS "x", p0."y" AS "y" FROM "posts" AS p0 WHERE (p0."title" = $1)) AS s1 ON TRUE}

    posts = subquery("posts" |> where(title: ^"hello") |> select([r], %{x: r.x, z: r.y}))
    query = "comments" |> join(:inner, [c], p in subquery(posts), on: true) |> select([_, p], p) |> plan()
    assert all(query) ==
           ~s{SELECT s1."x", s1."z" FROM "comments" AS c0 } <>
           ~s{INNER JOIN (SELECT p0."x" AS "x", p0."y" AS "z" FROM "posts" AS p0 WHERE (p0."title" = $1)) AS s1 ON TRUE}
  end

  test "join with prefix" do
    query = Schema |> join(:inner, [p], q in Schema2, on: p.x == q.z) |> select([], true) |> Map.put(:prefix, "prefix") |> plan()
    assert all(query) ==
           ~s{SELECT TRUE FROM "prefix"."schema" AS s0 INNER JOIN "prefix"."schema2" AS s1 ON s0."x" = s1."z"}

    query = Schema |> from(prefix: "first") |> join(:inner, [p], q in Schema2, on: p.x == q.z, prefix: "second") |> select([], true) |> Map.put(:prefix, "prefix") |> plan()
    assert all(query) ==
           ~s{SELECT TRUE FROM "first"."schema" AS s0 INNER JOIN "second"."schema2" AS s1 ON s0."x" = s1."z"}
  end

  test "join with fragment" do
    query = Schema
            |> join(:inner, [p], q in fragment("SELECT * FROM schema2 AS s2 WHERE s2.id = ? AND s2.field = ?", p.x, ^10))
            |> select([p], {p.id, ^0})
            |> where([p], p.id > 0 and p.id < ^100)
            |> plan()
    assert all(query) ==
           ~s{SELECT s0."id", $1 FROM "schema" AS s0 INNER JOIN } <>
           ~s{(SELECT * FROM schema2 AS s2 WHERE s2.id = s0."x" AND s2.field = $2) AS f1 ON TRUE } <>
           ~s{WHERE ((s0."id" > 0) AND (s0."id" < $3))}
  end

  test "join with fragment and on defined" do
    query = Schema
            |> join(:inner, [p], q in fragment("SELECT * FROM schema2"), on: q.id == p.id)
            |> select([p], {p.id, ^0})
            |> plan()
    assert all(query) ==
           ~s{SELECT s0."id", $1 FROM "schema" AS s0 INNER JOIN } <>
           ~s{(SELECT * FROM schema2) AS f1 ON f1."id" = s0."id"}
  end

  test "join with query interpolation" do
    inner = Ecto.Queryable.to_query(Schema2)
    query = from(p in Schema, left_join: c in ^inner, select: {p.id, c.id}) |> plan()
    assert all(query) ==
           "SELECT s0.\"id\", s1.\"id\" FROM \"schema\" AS s0 LEFT OUTER JOIN \"schema2\" AS s1 ON TRUE"
  end

  test "lateral join with fragment" do
    query = Schema
            |> join(:inner_lateral, [p], q in fragment("SELECT * FROM schema2 AS s2 WHERE s2.id = ? AND s2.field = ?", p.x, ^10))
            |> select([p, q], {p.id, q.z})
            |> where([p], p.id > 0 and p.id < ^100)
            |> plan()
    assert all(query) ==
           ~s{SELECT s0."id", f1."z" FROM "schema" AS s0 INNER JOIN LATERAL } <>
           ~s{(SELECT * FROM schema2 AS s2 WHERE s2.id = s0."x" AND s2.field = $1) AS f1 ON TRUE } <>
           ~s{WHERE ((s0."id" > 0) AND (s0."id" < $2))}
  end

  test "cross join" do
    query = from(p in Schema, cross_join: c in Schema2, select: {p.id, c.id}) |> plan()
    assert all(query) ==
           "SELECT s0.\"id\", s1.\"id\" FROM \"schema\" AS s0 CROSS JOIN \"schema2\" AS s1"
  end

  test "cross join with fragment" do
    query = from(p in Schema, cross_join: fragment("jsonb_each(?)", p.j), select: {p.id}) |> plan()
    assert all(query) ==
           ~s{SELECT s0."id" FROM "schema" AS s0 CROSS JOIN jsonb_each(s0."j") AS f1}
  end

  test "join produces correct bindings" do
    query = from(p in Schema, join: c in Schema2, on: true)
    query = from(p in query, join: c in Schema2, on: true, select: {p.id, c.id})
    query = plan(query)
    assert all(query) ==
           "SELECT s0.\"id\", s2.\"id\" FROM \"schema\" AS s0 INNER JOIN \"schema2\" AS s1 ON TRUE INNER JOIN \"schema2\" AS s2 ON TRUE"
  end

  describe "query interpolation parameters" do
    test "self join on subquery" do
      subquery = select(Schema, [r], %{x: r.x, y: r.y})
      query = subquery |> join(:inner, [c], p in subquery(subquery), on: true) |> plan()
      assert all(query) ==
             ~s{SELECT s0."x", s0."y" FROM "schema" AS s0 INNER JOIN } <>
             ~s{(SELECT s0."x" AS "x", s0."y" AS "y" FROM "schema" AS s0) } <>
             ~s{AS s1 ON TRUE}
    end

    test "self join on subquery with fragment" do
      subquery = select(Schema, [r], %{string: fragment("downcase(?)", ^"string")})
      query = subquery |> join(:inner, [c], p in subquery(subquery), on: true) |> plan()
      assert all(query) ==
             ~s{SELECT downcase($1) FROM "schema" AS s0 INNER JOIN } <>
             ~s{(SELECT downcase($2) AS "string" FROM "schema" AS s0) } <>
             ~s{AS s1 ON TRUE}
    end

    test "join on subquery with simple select" do
      subquery = select(Schema, [r], %{x: ^999, w: ^888})
      query = Schema
              |> select([r], %{y: ^666})
              |> join(:inner, [c], p in subquery(subquery), on: true)
              |> where([a, b], a.x == ^111)
              |> plan()

      assert all(query) ==
             ~s{SELECT $1 FROM "schema" AS s0 INNER JOIN } <>
             ~s{(SELECT $2 AS "x", $3 AS "w" FROM "schema" AS s0) AS s1 ON TRUE } <>
             ~s{WHERE (s0."x" = $4)}
    end
  end

  ## Associations

  test "association join belongs_to" do
    query = Schema2 |> join(:inner, [c], p in assoc(c, :post)) |> select([], true) |> plan()
    assert all(query) ==
           "SELECT TRUE FROM \"schema2\" AS s0 INNER JOIN \"schema\" AS s1 ON s1.\"x\" = s0.\"z\""
  end

  test "association join has_many" do
    query = Schema |> join(:inner, [p], c in assoc(p, :comments)) |> select([], true) |> plan()
    assert all(query) ==
           "SELECT TRUE FROM \"schema\" AS s0 INNER JOIN \"schema2\" AS s1 ON s1.\"z\" = s0.\"x\""
  end

  test "association join has_one" do
    query = Schema |> join(:inner, [p], pp in assoc(p, :permalink)) |> select([], true) |> plan()
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
    update = from("schema", update: [set: [z: "foo"]]) |> plan(:update_all)
    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {update, [], [:x, :y]}, [:z])
    assert query == ~s{INSERT INTO "schema" AS s0 ("x","y") VALUES ($1,$2) ON CONFLICT ("x","y") DO UPDATE SET "z" = 'foo' RETURNING "z"}

    # For :replace_all
    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {[:x, :y], [], [:id]}, [])
    assert query == ~s{INSERT INTO "schema" ("x","y") VALUES ($1,$2) ON CONFLICT ("id") DO UPDATE SET "x" = EXCLUDED."x","y" = EXCLUDED."y"}

    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {[:x, :y], [], []}, [])
    assert query == ~s{INSERT INTO "schema" ("x","y") VALUES ($1,$2) ON CONFLICT DO UPDATE SET "x" = EXCLUDED."x","y" = EXCLUDED."y"}

    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {[:x, :y], [], {:constraint, :foo}}, [])
    assert query == ~s{INSERT INTO "schema" ("x","y") VALUES ($1,$2) ON CONFLICT ON CONSTRAINT \"foo\" DO UPDATE SET "x" = EXCLUDED."x","y" = EXCLUDED."y"}

    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {[:x, :y], [], {:unsafe_fragment, "(\"id\")"}}, [])
    assert query == ~s{INSERT INTO "schema" ("x","y") VALUES ($1,$2) ON CONFLICT (\"id\") DO UPDATE SET "x" = EXCLUDED."x","y" = EXCLUDED."y"}
  end

  test "update" do
    query = update(nil, "schema", [:x, :y], [id: 1], [])
    assert query == ~s{UPDATE "schema" SET "x" = $1, "y" = $2 WHERE "id" = $3}

    query = update(nil, "schema", [:x, :y], [id: 1], [:z])
    assert query == ~s{UPDATE "schema" SET "x" = $1, "y" = $2 WHERE "id" = $3 RETURNING "z"}

    query = update("prefix", "schema", [:x, :y], [id: 1], [])
    assert query == ~s{UPDATE "prefix"."schema" SET "x" = $1, "y" = $2 WHERE "id" = $3}

    query = update("prefix", "schema", [:x, :y], [id: 1, updated_at: nil], [])
    assert query == ~s{UPDATE "prefix"."schema" SET "x" = $1, "y" = $2 WHERE "id" = $3 AND "updated_at" IS NULL}
  end

  test "delete" do
    query = delete(nil, "schema", [x: 1, y: 2], [])
    assert query == ~s{DELETE FROM "schema" WHERE "x" = $1 AND "y" = $2}

    query = delete(nil, "schema", [x: 1, y: 2], [:z])
    assert query == ~s{DELETE FROM "schema" WHERE "x" = $1 AND "y" = $2 RETURNING "z"}

    query = delete("prefix", "schema", [x: 1, y: 2], [])
    assert query == ~s{DELETE FROM "prefix"."schema" WHERE "x" = $1 AND "y" = $2}

    query = delete("prefix", "schema", [x: nil, y: 1], [])
    assert query == ~s{DELETE FROM "prefix"."schema" WHERE "x" IS NULL AND "y" = $1}
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
               {:add, :tags, {:array, :string}, [default: []]},
               {:add, :languages, {:array, :string}, [default: ["pt", "es"]]},
               {:add, :limits, {:array, :integer}, [default: [100, 30_000]]}]}

    assert execute_ddl(create) == ["""
    CREATE TABLE "posts" ("name" varchar(20) DEFAULT 'Untitled' NOT NULL,
    "price" numeric(8,2) DEFAULT expr,
    "on_hand" integer DEFAULT 0 NULL,
    "published_at" time without time zone NULL,
    "is_active" boolean DEFAULT true,
    "tags" varchar(255)[] DEFAULT ARRAY[]::varchar[],
    "languages" varchar(255)[] DEFAULT ARRAY['pt','es']::varchar[],
    "limits" integer[] DEFAULT ARRAY[100,30000]::integer[])
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
      [~s|CREATE TABLE "posts" ("id" serial, "created_at" timestamp(0), PRIMARY KEY ("id")) WITH FOO=BAR|]
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

  test "create table with binary column and null-byte default" do
    create = {:create, table(:blobs),
              [{:add, :blob, :binary, [default: <<0>>]}]}

    assert_raise ArgumentError, ~r/"\\x00"/, fn ->
      execute_ddl(create)
    end
  end

  test "create table with binary column and null-byte-containing default" do
    create = {:create, table(:blobs),
              [{:add, :blob, :binary, [default: "foo" <> <<0>>]}]}

    assert_raise ArgumentError, ~r/"\\x666f6f00"/, fn ->
      execute_ddl(create)
    end
  end

  test "create table with binary column and UTF-8 default" do
    create = {:create, table(:blobs),
              [{:add, :blob, :binary, [default: "foo"]}]}

    assert execute_ddl(create) == ["""
    CREATE TABLE "blobs" ("blob" bytea DEFAULT 'foo')
    """ |> remove_newlines]
  end

  test "create table with binary column and hex bytea literal default" do
    create = {:create, table(:blobs),
              [{:add, :blob, :binary, [default: "\\x666F6F"]}]}

    assert execute_ddl(create) == ["""
    CREATE TABLE "blobs" ("blob" bytea DEFAULT '\\x666F6F')
    """ |> remove_newlines]
  end

  test "create table with binary column and hex bytea literal null-byte" do
    create = {:create, table(:blobs),
              [{:add, :blob, :binary, [default: "\\x00"]}]}

    assert execute_ddl(create) == ["""
    CREATE TABLE "blobs" ("blob" bytea DEFAULT '\\x00')
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
    assert execute_ddl(create) == [~s|CREATE TABLE "posts" ("a" jsonb DEFAULT '{"baz":"boom","foo":"bar"}')|]
  end

  test "create table with a map column, and a string default" do
    create = {:create, table(:posts),
              [
                {:add, :a, :map, [default: ~s|{"foo":"bar","baz":"boom"}|]}
              ]
            }
    assert execute_ddl(create) == [~s|CREATE TABLE "posts" ("a" jsonb DEFAULT '{"foo":"bar","baz":"boom"}')|]
  end

  test "create table with time columns" do
    create = {:create, table(:posts),
              [{:add, :published_at, :time, [precision: 3]},
               {:add, :submitted_at, :time, []}]}

    assert execute_ddl(create) == [~s|CREATE TABLE "posts" ("published_at" time(0), "submitted_at" time(0))|]
  end

  test "create table with time_usec columns" do
    create = {:create, table(:posts),
              [{:add, :published_at, :time_usec, [precision: 3]},
               {:add, :submitted_at, :time_usec, []}]}

    assert execute_ddl(create) == [~s|CREATE TABLE "posts" ("published_at" time(3), "submitted_at" time)|]
  end

  test "create table with utc_datetime columns" do
    create = {:create, table(:posts),
              [{:add, :published_at, :utc_datetime, [precision: 3]},
               {:add, :submitted_at, :utc_datetime, []}]}

    assert execute_ddl(create) == [~s|CREATE TABLE "posts" ("published_at" timestamp(0), "submitted_at" timestamp(0))|]
  end

  test "create table with utc_datetime_usec columns" do
    create = {:create, table(:posts),
              [{:add, :published_at, :utc_datetime_usec, [precision: 3]},
               {:add, :submitted_at, :utc_datetime_usec, []}]}

    assert execute_ddl(create) == [~s|CREATE TABLE "posts" ("published_at" timestamp(3), "submitted_at" timestamp)|]
  end

  test "create table with naive_datetime columns" do
    create = {:create, table(:posts),
              [{:add, :published_at, :naive_datetime, [precision: 3]},
               {:add, :submitted_at, :naive_datetime, []}]}

    assert execute_ddl(create) == [~s|CREATE TABLE "posts" ("published_at" timestamp(0), "submitted_at" timestamp(0))|]
  end

  test "create table with naive_datetime_usec columns" do
    create = {:create, table(:posts),
              [{:add, :published_at, :naive_datetime_usec, [precision: 3]},
               {:add, :submitted_at, :naive_datetime_usec, []}]}

    assert execute_ddl(create) == [~s|CREATE TABLE "posts" ("published_at" timestamp(3), "submitted_at" timestamp)|]
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
              {:modify, :status, :string, from: :integer},
              {:modify, :user_id, :integer, from: %Reference{table: :users}},
              {:modify, :group_id, %Reference{table: :groups, column: :gid}, from: %Reference{table: :groups}},
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
    ALTER COLUMN "status" TYPE varchar(255),
    DROP CONSTRAINT "posts_user_id_fkey",
    ALTER COLUMN "user_id" TYPE integer,
    DROP CONSTRAINT "posts_group_id_fkey",
    ALTER COLUMN "group_id" TYPE bigint,
    ADD CONSTRAINT "posts_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "groups"("gid"),
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

  test "create index if not exists concurrently" do
    create = {:create_if_not_exists, index(:posts, [:permalink], concurrently: true)}

    assert_raise ArgumentError,
                 "concurrent index and create_if_not_exists is not supported by the Postgres adapter",
                 fn -> execute_ddl(create) end
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

  test "logs DDL notices" do
    result = make_result("INFO")
    assert SQL.ddl_logs(result) == [{:info, ~s(table "foo" exists, skipping), []}]

    result = make_result("WARNING")
    assert SQL.ddl_logs(result) == [{:warn, ~s(table "foo" exists, skipping), []}]

    result = make_result("ERROR")
    assert SQL.ddl_logs(result) == [{:error, ~s(table "foo" exists, skipping), []}]
  end

  defp make_result(level) do
    %Postgrex.Result{
      messages: [
        %{
          message: ~s(table "foo" exists, skipping),
          severity: level
        }
      ]
    }
  end

  defp remove_newlines(string) do
    string |> String.trim |> String.replace("\n", " ")
  end
end
