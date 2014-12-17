defmodule Ecto.Adapters.Postgres.SQLTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto.Query.Normalizer, only: [normalize: 1]
  alias Ecto.Adapters.Postgres.SQL
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
    assert SQL.select(query) == {~s{SELECT m0."x" FROM "model" AS m0}, []}
  end

  test "from without model" do
    query = "posts" |> select([r], r.x) |> normalize
    assert SQL.select(query) == {~s{SELECT p0."x" FROM "posts" AS p0}, []}
  end

  test "select" do
    query = Model |> select([r], {r.x, r.y}) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x", m0."y" FROM "model" AS m0}, []}

    query = Model |> select([r], [r.x, r.y]) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x", m0."y" FROM "model" AS m0}, []}
  end

  test "distinct" do
    query = Model |> distinct([r], r.x) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.select(query) == {~s{SELECT DISTINCT ON (m0."x") m0."x", m0."y" FROM "model" AS m0}, []}

    query = Model |> distinct([r], 2) |> select([r], r.x) |> normalize
    assert SQL.select(query) == {~s{SELECT DISTINCT ON (2) m0."x" FROM "model" AS m0}, []}

    query = Model |> distinct([r], [r.x, r.y]) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.select(query) == {~s{SELECT DISTINCT ON (m0."x", m0."y") m0."x", m0."y" FROM "model" AS m0}, []}
  end

  test "where" do
    query = Model |> where([r], r.x == 42) |> where([r], r.y != 43) |> select([r], r.x) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x" FROM "model" AS m0 WHERE (m0."x" = 42) AND (m0."y" != 43)}, []}
  end

  test "order by" do
    query = Model |> order_by([r], r.x) |> select([r], r.x) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x" FROM "model" AS m0 ORDER BY m0."x"}, []}

    query = Model |> order_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x" FROM "model" AS m0 ORDER BY m0."x", m0."y"}, []}

    query = Model |> order_by([r], [asc: r.x, desc: r.y]) |> select([r], r.x) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x" FROM "model" AS m0 ORDER BY m0."x", m0."y" DESC}, []}
  end

  test "limit and offset" do
    query = Model |> limit([r], 3) |> select([], 0) |> normalize
    assert SQL.select(query) == {~s{SELECT 0 FROM "model" AS m0 LIMIT 3}, []}

    query = Model |> offset([r], 5) |> select([], 0) |> normalize
    assert SQL.select(query) == {~s{SELECT 0 FROM "model" AS m0 OFFSET 5}, []}

    query = Model |> offset([r], 5) |> limit([r], 3) |> select([], 0) |> normalize
    assert SQL.select(query) == {~s{SELECT 0 FROM "model" AS m0 LIMIT 3 OFFSET 5}, []}
  end

  test "lock" do
    query = Model |> lock(true) |> select([], 0) |> normalize
    assert SQL.select(query) == {~s{SELECT 0 FROM "model" AS m0 FOR UPDATE}, []}

    query = Model |> lock("FOR SHARE NOWAIT") |> select([], 0) |> normalize
    assert SQL.select(query) == {~s{SELECT 0 FROM "model" AS m0 FOR SHARE NOWAIT}, []}
  end

  test "string escape" do
    query = Model |> select([], "'\\  ") |> normalize
    assert SQL.select(query) == {~s{SELECT '''\\  ' FROM "model" AS m0}, []}

    query = Model |> select([], "'") |> normalize
    assert SQL.select(query) == {~s{SELECT '''' FROM "model" AS m0}, []}
  end

  test "binary ops" do
    query = Model |> select([r], r.x == 2) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x" = 2 FROM "model" AS m0}, []}

    query = Model |> select([r], r.x != 2) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x" != 2 FROM "model" AS m0}, []}

    query = Model |> select([r], r.x <= 2) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x" <= 2 FROM "model" AS m0}, []}

    query = Model |> select([r], r.x >= 2) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x" >= 2 FROM "model" AS m0}, []}

    query = Model |> select([r], r.x < 2) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x" < 2 FROM "model" AS m0}, []}

    query = Model |> select([r], r.x > 2) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x" > 2 FROM "model" AS m0}, []}

    query = Model |> select([r], r.x and false) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x" AND FALSE FROM "model" AS m0}, []}

    query = Model |> select([r], r.x or false) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x" OR FALSE FROM "model" AS m0}, []}
  end

  test "is_nil" do
    query = Model |> select([r], is_nil(r.x)) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x" IS NULL FROM "model" AS m0}, []}

    query = Model |> select([r], not is_nil(r.x)) |> normalize
    assert SQL.select(query) == {~s{SELECT NOT (m0."x" IS NULL) FROM "model" AS m0}, []}
  end

  test "fragments" do
    query = Model |> select([r], ~f[downcase(#{r.x})]) |> normalize
    assert SQL.select(query) == {~s{SELECT downcase(m0."x") FROM "model" AS m0}, []}

    value = 13
    query = Model |> select([r], ~f[downcase(#{r.x}, #{^value})]) |> normalize
    assert SQL.select(query) == {"SELECT downcase(m0.\"x\", $1) FROM \"model\" AS m0", '\r'}
  end

  test "literals" do
    query = Model |> select([], nil) |> normalize
    assert SQL.select(query) == {~s{SELECT NULL FROM "model" AS m0}, []}

    query = Model |> select([], true) |> normalize
    assert SQL.select(query) == {~s{SELECT TRUE FROM "model" AS m0}, []}

    query = Model |> select([], false) |> normalize
    assert SQL.select(query) == {~s{SELECT FALSE FROM "model" AS m0}, []}

    query = Model |> select([], "abc") |> normalize
    assert SQL.select(query) == {~s{SELECT 'abc' FROM "model" AS m0}, []}

    query = Model |> select([], <<0, ?a,?b,?c>>) |> normalize
    assert SQL.select(query) == {~s{SELECT '\\x00616263' FROM "model" AS m0}, []}

    query = Model |> select([], uuid(<<0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15>>)) |> normalize
    assert SQL.select(query) == {~s{SELECT '000102030405060708090A0B0C0D0E0F' FROM "model" AS m0}, []}

    query = Model |> select([], uuid("\0\x01\x02\x03\x04\x05\x06\a\b\t\n\v\f\r\x0E\x0F")) |> normalize
    assert SQL.select(query) == {~s{SELECT '000102030405060708090A0B0C0D0E0F' FROM "model" AS m0}, []}

    query = Model |> select([], 123) |> normalize
    assert SQL.select(query) == {~s{SELECT 123 FROM "model" AS m0}, []}

    query = Model |> select([], 123.0) |> normalize
    assert SQL.select(query) == {~s{SELECT 123.0::float FROM "model" AS m0}, []}
  end

  test "interpolated values" do
    query = Model
            |> select([], ^0)
            |> join(:inner, [], Model2, ^true)
            |> join(:inner, [], Model2, ^false)
            |> where([], ^true)
            |> where([], ^false)
            |> group_by([], ^1)
            |> group_by([], ^2)
            |> having([], ^true)
            |> having([], ^false)
            |> order_by([], ^3)
            |> order_by([], ^4)
            |> limit([], ^5)
            |> offset([], ^6)
            |> normalize

    result =
      "SELECT $1 FROM \"model\" AS m0 INNER JOIN \"model2\" AS m1 ON $2 " <>
      "INNER JOIN \"model2\" AS m2 ON $3 WHERE ($4) AND ($5) " <>
      "GROUP BY $6, $7 HAVING ($8) AND ($9) " <>
      "ORDER BY $10, $11 LIMIT $12 OFFSET $13"

    assert SQL.select(query) == {String.rstrip(result),
                                 [0, true, false, true, false, 1, 2, true, false, 3, 4, 5, 6]}

    value = Decimal.new("42")
    query = Model |> select([], ^value) |> normalize
    assert SQL.select(query) == {~s{SELECT $1 FROM "model" AS m0}, [value]}

    value = %Ecto.DateTime{year: 2014, month: 1, day: 16, hour: 20, min: 26, sec: 51}
    query = Model |> select([], ^value) |> normalize
    assert SQL.select(query) == {~s{SELECT $1 FROM "model" AS m0}, [value]}
  end

  test "nested expressions" do
    z = 123
    query = from(r in Model, []) |> select([r], r.x and (r.y > ^(-z)) or true) |> normalize
    assert SQL.select(query) == {~s{SELECT (m0."x" AND (m0."y" > $1)) OR TRUE FROM "model" AS m0}, [-123]}
  end

  test "insert" do
    query = SQL.insert(%Model{x: 123, y: "456"}, [:id])
    assert query == {~s{INSERT INTO "model" ("x", "y") VALUES ($1, $2) RETURNING "id"}, [123, "456"]}
  end

  test "insert with missing values" do
    query = SQL.insert(%Model{x: 123}, [:id, :y])
    assert query == {~s{INSERT INTO "model" ("x") VALUES ($1) RETURNING "id", "y"}, [123]}

    query = SQL.insert(%Model{}, [:id, :y])
    assert query == {~s{INSERT INTO "model" DEFAULT VALUES RETURNING "id", "y"}, []}
  end

  test "insert with list" do
    query = SQL.insert(%Model3{list1: ["a", "b", "c"], list2: [1, 2, 3]}, [:id])
    assert query == {~s{INSERT INTO "model3" ("list1", "list2") VALUES ($1, $2) RETURNING "id"}, [["a", "b", "c"], [1, 2, 3]]}
  end

  test "insert with binary" do
    query = SQL.insert(%Model3{binary: <<1, 2, 3>>}, [:id])
    assert query == {~s{INSERT INTO "model3" ("binary") VALUES ($1) RETURNING "id"}, [<<1, 2, 3>>]}
  end

  test "update" do
    query = SQL.update(%Model{id: 42, x: 123, y: "456"})
    assert query == {~s{UPDATE "model" SET "x" = $1, "y" = $2 WHERE "id" = $3}, [123, "456", 42]}
  end

  test "delete" do
    query = SQL.delete(%Model{id: 42, x: 123, y: "456"})
    assert query == {~s{DELETE FROM "model" WHERE "id" = $1}, [42]}
  end

  test "table name" do
    query = from(SomeModel, select: 0) |> normalize
    assert SQL.select(query) == {~s{SELECT 0 FROM "weird_name_123" AS w0}, []}
  end

  test "update all" do
    query = Model |> Queryable.to_query |> normalize
    assert SQL.update_all(query, [x: 0], %{}) ==
           {~s{UPDATE "model" AS m0 SET "x" = 0}, []}

    query = from(e in Model, where: e.x == 123) |> normalize
    assert SQL.update_all(query, [x: 0], %{}) ==
           {~s{UPDATE "model" AS m0 SET "x" = 0 WHERE (m0."x" = 123)}, []}

    query = Model |> Queryable.to_query |> normalize
    assert SQL.update_all(query, [x: 0, y: "123"], %{}) ==
           {~s{UPDATE "model" AS m0 SET "x" = 0, "y" = '123'}, []}

    query = Model |> Queryable.to_query |> normalize
    assert SQL.update_all(query, [x: quote do: ^0], %{0 => 42}) ==
           {~s{UPDATE "model" AS m0 SET "x" = $1}, [42]}
  end

  test "delete all" do
    query = Model |> Queryable.to_query |> normalize
    assert SQL.delete_all(query) == {~s{DELETE FROM "model" AS m0}, []}

    query = from(e in Model, where: e.x == 123) |> normalize
    assert SQL.delete_all(query) ==
           {~s{DELETE FROM "model" AS m0 WHERE (m0."x" = 123)}, []}
  end

  test "in expression" do
    query = Model |> select([e], 1 in []) |> normalize
    assert SQL.select(query) == {~s{SELECT 1 = ANY (ARRAY[]) FROM "model" AS m0}, []}

    query = Model |> select([e], 1 in [1,e.x,3]) |> normalize
    assert SQL.select(query) == {~s{SELECT 1 = ANY (ARRAY[1, m0."x", 3]) FROM "model" AS m0}, []}
  end

  test "having" do
    query = Model |> having([p], p.x == p.x) |> select([], 0) |> normalize
    assert SQL.select(query) == {~s{SELECT 0 FROM "model" AS m0 HAVING (m0."x" = m0."x")}, []}

    query = Model |> having([p], p.x == p.x) |> having([p], p.y == p.y) |> select([], 0) |> normalize
    assert SQL.select(query) == {~s{SELECT 0 FROM "model" AS m0 HAVING (m0."x" = m0."x") AND (m0."y" = m0."y")}, []}
  end

  test "group by" do
    query = Model |> group_by([r], r.x) |> select([r], r.x) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x" FROM "model" AS m0 GROUP BY m0."x"}, []}

    query = Model |> group_by([r], 2) |> select([r], r.x) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x" FROM "model" AS m0 GROUP BY 2}, []}

    query = Model |> group_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x" FROM "model" AS m0 GROUP BY m0."x", m0."y"}, []}
  end

  test "sigils" do
    query = Model |> select([], ~s"abc" in ~w(abc def)) |> normalize
    assert SQL.select(query) == {~s{SELECT 'abc' = ANY (ARRAY['abc', 'def']) FROM "model" AS m0}, []}
  end

  defmodule Rec, do: defstruct [:x]

  defp fun(x), do: x+x

  test "query interpolation" do
    r = %Rec{x: 123}
    query = Model |> select([r], r.x > ^(1 + 2 + 3)) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x" > $1 FROM "model" AS m0}, [6]}

    query = Model |> select([r], r.x > ^fun(r.x)) |> normalize
    assert SQL.select(query) == {~s{SELECT m0."x" > $1 FROM "model" AS m0}, [246]}
  end

  test "join" do
    query = Model |> join(:inner, [p], q in Model2, p.x == q.z) |> select([], 0) |> normalize
    assert SQL.select(query) ==
           {~s{SELECT 0 FROM "model" AS m0 INNER JOIN "model2" AS m1 ON m0."x" = m1."z"}, []}

    query = Model |> join(:inner, [p], q in Model2, p.x == q.z) |> join(:inner, [], Model, true) |> select([], 0) |> normalize
    assert SQL.select(query) ==
           {~s{SELECT 0 FROM "model" AS m0 INNER JOIN "model2" AS m1 ON m0."x" = m1."z" } <>
            ~s{INNER JOIN "model" AS m2 ON TRUE}, []}
  end

  test "join with nothing bound" do
    query = Model |> join(:inner, [], q in Model2, q.z == q.z) |> select([], 0) |> normalize
    assert SQL.select(query) ==
           {~s{SELECT 0 FROM "model" AS m0 INNER JOIN "model2" AS m1 ON m1."z" = m1."z"}, []}
  end

  test "join without model" do
    query = "posts" |> join(:inner, [p], q in "comments", p.x == q.z) |> select([], 0) |> normalize
    assert SQL.select(query) ==
           {~s{SELECT 0 FROM "posts" AS p0 INNER JOIN "comments" AS c0 ON p0."x" = c0."z"}, []}
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
    assert SQL.select(query) ==
           {~s{SELECT 0 FROM "comments" AS c0 INNER JOIN "posts" AS p0 ON p0."a" = c0."b"}, []}
  end

  test "association join has_many" do
    query = Post |> join(:inner, [p], c in p.comments) |> select([], 0) |> normalize
    assert SQL.select(query) ==
           {~s{SELECT 0 FROM "posts" AS p0 INNER JOIN "comments" AS c0 ON c0."d" = p0."c"}, []}
  end

  test "association join has_one" do
    query = Post |> join(:inner, [p], pp in p.permalink) |> select([], 0) |> normalize
    assert SQL.select(query) ==
           {~s{SELECT 0 FROM "posts" AS p0 INNER JOIN "permalinks" AS p1 ON p1."f" = p0."e"}, []}
  end

  test "association join with on" do
    query = Post |> join(:inner, [p], c in p.comments, 1 == 2) |> select([], 0) |> normalize
    assert SQL.select(query) ==
           {~s{SELECT 0 FROM "posts" AS p0 INNER JOIN "comments" AS c0 ON (1 = 2) AND (c0."d" = p0."c")}, []}
  end

  test "join produces correct bindings" do
    query = from(p in Post, join: c in Comment, on: true)
    query = from(p in query, join: c in Comment, on: true, select: {p.id, c.id})
    query = normalize(query)
    assert SQL.select(query) ==
           {~s{SELECT p0."id", c1."id" FROM "posts" AS p0 INNER JOIN "comments" AS c0 ON TRUE INNER JOIN "comments" AS c1 ON TRUE}, []}
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
    assert SQL.insert(model, [:pk]) ==
           {~s{INSERT INTO "model" ("x", "y") VALUES ($1, $2) RETURNING "pk"}, [10, 30]}

    model = %PKModel{x: 10, pk: 20, y: 30}
    assert SQL.insert(model, []) ==
           {~s{INSERT INTO "model" ("pk", "x", "y") VALUES ($1, $2, $3)}, [20, 10, 30]}
  end

  test "send explicit set primary key" do
    model = %Model{id: 123, x: 0, y: 2}
    assert SQL.insert(model, []) ==
           {~s{INSERT INTO "model" ("id", "x", "y") VALUES ($1, $2, $3)}, [123, 0, 2]}
  end
end
