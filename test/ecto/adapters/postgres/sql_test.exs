defmodule Ecto.Adapters.Postgres.SQLTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto.Query.Util, only: [normalize: 1]
  alias Ecto.Adapters.Postgres.SQL
  alias Ecto.Queryable

  defmodule Model do
    use Ecto.Model

    queryable "model" do
      field :x, :integer
      field :y, :integer
    end
  end

  defmodule Model2 do
    use Ecto.Model
    queryable "model2" do
      field :z, :integer
    end
  end

  defmodule SomeModel do
    use Ecto.Model

    queryable "weird_name_123" do
    end
  end

  test "from" do
    query = from(Model) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.x\nFROM model AS m0"
  end

  test "from without entity" do
    query = from("posts") |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT p0.x\nFROM posts AS p0"
  end

  test "select" do
    query = from(Model) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.select(query) == "SELECT m0.x, m0.y\nFROM model AS m0"

    query = from(Model) |> select([r], {r.x, r.y + 123}) |> normalize
    assert SQL.select(query) == "SELECT m0.x, m0.y + 123\nFROM model AS m0"
  end

  test "where" do
    query = from(Model) |> where([r], r.x != nil) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.x\nFROM model AS m0\nWHERE (m0.x IS NOT NULL)"

    query = from(Model) |> where([r], r.x == 42) |> where([r], r.y != 43) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.x\nFROM model AS m0\nWHERE (m0.x = 42) AND (m0.y != 43)"
  end

  test "order by" do
    query = from(Model) |> order_by([r], r.x) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.x\nFROM model AS m0\nORDER BY m0.x"

    query = from(Model) |> order_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.x\nFROM model AS m0\nORDER BY m0.x, m0.y"

    query = from(Model) |> order_by([r], [asc: r.x, desc: r.y]) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.x\nFROM model AS m0\nORDER BY m0.x ASC, m0.y DESC"
  end

  test "limit and offset" do
    query = from(Model) |> limit([], 3) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM model AS m0\nLIMIT 3"

    query = from(Model) |> offset([], 5) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM model AS m0\nOFFSET 5"

    query = from(Model) |> offset([], 5) |> limit([], 3) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM model AS m0\nLIMIT 3\nOFFSET 5"
  end

  test "variable binding" do
    x = 123
    query = from(Model) |> select([], ^x) |> normalize
    assert SQL.select(query) == "SELECT 123\nFROM model AS m0"

    query = from(Model) |> select([r], ^x + r.y) |> normalize
    assert SQL.select(query) == "SELECT 123 + m0.y\nFROM model AS m0"
  end

  test "string escape" do
    x = "'\\ \n"
    query = from(Model) |> select([], ^x) |> normalize
    assert SQL.select(query) == "SELECT '''\\ \n'::text\nFROM model AS m0"

    query = from(Model) |> select([], "'") |> normalize
    assert SQL.select(query) == "SELECT ''''::text\nFROM model AS m0"
  end

  test "unary ops" do
    query = from(Model) |> select([r], +r.x) |> normalize
    assert SQL.select(query) == "SELECT +m0.x\nFROM model AS m0"

    query = from(Model) |> select([r], -r.x) |> normalize
    assert SQL.select(query) == "SELECT -m0.x\nFROM model AS m0"
  end

  test "binary ops" do
    query = from(Model) |> select([r], r.x == 2) |> normalize
    assert SQL.select(query) == "SELECT m0.x = 2\nFROM model AS m0"

    query = from(Model) |> select([r], r.x != 2) |> normalize
    assert SQL.select(query) == "SELECT m0.x != 2\nFROM model AS m0"

    query = from(Model) |> select([r], r.x <= 2) |> normalize
    assert SQL.select(query) == "SELECT m0.x <= 2\nFROM model AS m0"

    query = from(Model) |> select([r], r.x >= 2) |> normalize
    assert SQL.select(query) == "SELECT m0.x >= 2\nFROM model AS m0"

    query = from(Model) |> select([r], r.x < 2) |> normalize
    assert SQL.select(query) == "SELECT m0.x < 2\nFROM model AS m0"

    query = from(Model) |> select([r], r.x > 2) |> normalize
    assert SQL.select(query) == "SELECT m0.x > 2\nFROM model AS m0"

    query = from(Model) |> select([r], r.x + 2) |> normalize
    assert SQL.select(query) == "SELECT m0.x + 2\nFROM model AS m0"

    query = from(Model) |> select([r], r.x - 2) |> normalize
    assert SQL.select(query) == "SELECT m0.x - 2\nFROM model AS m0"

    query = from(Model) |> select([r], r.x * 2) |> normalize
    assert SQL.select(query) == "SELECT m0.x * 2\nFROM model AS m0"

    query = from(Model) |> select([r], r.x / 2) |> normalize
    assert SQL.select(query) == "SELECT m0.x / 2::float\nFROM model AS m0"

    query = from(Model) |> select([r], r.x and false) |> normalize
    assert SQL.select(query) == "SELECT m0.x AND FALSE\nFROM model AS m0"

    query = from(Model) |> select([r], r.x or false) |> normalize
    assert SQL.select(query) == "SELECT m0.x OR FALSE\nFROM model AS m0"
  end

  test "binary op null check" do
    query = from(Model) |> select([r], r.x == nil) |> normalize
    assert SQL.select(query) == "SELECT m0.x IS NULL\nFROM model AS m0"

    query = from(Model) |> select([r], nil == r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.x IS NULL\nFROM model AS m0"

    query = from(Model) |> select([r], r.x != nil) |> normalize
    assert SQL.select(query) == "SELECT m0.x IS NOT NULL\nFROM model AS m0"

    query = from(Model) |> select([r], nil != r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.x IS NOT NULL\nFROM model AS m0"
  end

  test "literals" do
    query = from(Model) |> select([], nil) |> normalize
    assert SQL.select(query) == "SELECT NULL\nFROM model AS m0"

    query = from(Model) |> select([], true) |> normalize
    assert SQL.select(query) == "SELECT TRUE\nFROM model AS m0"

    query = from(Model) |> select([], false) |> normalize
    assert SQL.select(query) == "SELECT FALSE\nFROM model AS m0"

    query = from(Model) |> select([], "abc") |> normalize
    assert SQL.select(query) == "SELECT 'abc'::text\nFROM model AS m0"

    query = from(Model) |> select([], <<?a,?b,?c>>) |> normalize
    assert SQL.select(query) == "SELECT 'abc'::text\nFROM model AS m0"

    query = from(Model) |> select([], binary(<<0,1,2>>)) |> normalize
    assert SQL.select(query) == "SELECT '\\x000102'::bytea\nFROM model AS m0"

    query = from(Model) |> select([], 123) |> normalize
    assert SQL.select(query) == "SELECT 123\nFROM model AS m0"

    query = from(Model) |> select([], 123.0) |> normalize
    assert SQL.select(query) == "SELECT 123.0\nFROM model AS m0"
  end

  test "nested expressions" do
    z = 123
    query = from(r in Model) |> select([r], r.x + (r.y + ^(-z)) - 3) |> normalize
    assert SQL.select(query) == "SELECT (m0.x + (m0.y + -123)) - 3\nFROM model AS m0"
  end

  test "use correct bindings" do
    query = from(r in Model) |> select([not_r], not_r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.x\nFROM model AS m0"
  end

  test "insert" do
    query = SQL.insert(Model.Entity[x: 123, y: "456"])
    assert query == "INSERT INTO model (x, y)\nVALUES (123, '456'::text)\nRETURNING id"
  end

  test "update" do
    query = SQL.update(Model.Entity[id: 42, x: 123, y: "456"])
    assert query == "UPDATE model SET x = 123, y = '456'::text\nWHERE id = 42"
  end

  test "delete" do
    query = SQL.delete(Model.Entity[id: 42, x: 123, y: "456"])
    assert query == "DELETE FROM model WHERE id = 42"
  end

  test "table name" do
    query = from(SomeModel, select: 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM weird_name_123 AS w0"
  end

  test "update all" do
    query = Model |> Queryable.to_query |> normalize
    assert SQL.update_all(query, x: 0) == "UPDATE model AS m0\nSET x = 0"

    query = from(e in Model, where: e.x == 123) |> normalize
    assert SQL.update_all(query, x: 0) ==
           "UPDATE model AS m0\nSET x = 0\nWHERE (m0.x = 123)"

    query = Model |> Queryable.to_query |> normalize
    assert SQL.update_all(query, x: quote do &0.x + 1 end) ==
           "UPDATE model AS m0\nSET x = m0.x + 1"

    query = Model |> Queryable.to_query |> normalize
    assert SQL.update_all(query, x: 0, y: "123") ==
           "UPDATE model AS m0\nSET x = 0, y = '123'::text"
  end

  test "delete all" do
    query = Model |> Queryable.to_query |> normalize
    assert SQL.delete_all(query) == "DELETE FROM model AS m0"

    query = from(e in Model, where: e.x == 123) |> normalize
    assert SQL.delete_all(query) ==
           "DELETE FROM model AS m0\nWHERE (m0.x = 123)"
  end

  test "in expression" do
    query = from(Model) |> select([e], 1 in [1,e.x,3]) |> normalize
    assert SQL.select(query) == "SELECT 1 = ANY (ARRAY[1, m0.x, 3])\nFROM model AS m0"

    query = from(Model) |> select([e], e.x in 1..3) |> normalize
    assert SQL.select(query) == "SELECT m0.x BETWEEN 1 AND 3\nFROM model AS m0"

    query = from(Model) |> select([e], 1 in 1..(e.x + 5)) |> normalize
    assert SQL.select(query) == "SELECT 1 BETWEEN 1 AND m0.x + 5\nFROM model AS m0"
  end

  test "list expression" do
    query = from(e in Model) |> where([e], [e.x, e.y] == nil) |> select([e], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM model AS m0\nWHERE (ARRAY[m0.x, m0.y] IS NULL)"
  end

  test "having" do
    query = from(Model) |> having([p], p.x == p.x) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM model AS m0\nHAVING (m0.x = m0.x)"

    query = from(Model) |> having([p], p.x == p.x) |> having([p], p.y == p.y) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM model AS m0\nHAVING (m0.x = m0.x) AND (m0.y = m0.y)"
  end

  test "group by" do
    query = from(Model) |> group_by([r], r.x) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.x\nFROM model AS m0\nGROUP BY m0.x"

    query = from(Model) |> group_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.x\nFROM model AS m0\nGROUP BY m0.x, m0.y"

    query = from(Model) |> group_by([r], r) |> select([r], r.x) |> normalize
    assert SQL.select(query) == "SELECT m0.x\nFROM model AS m0\nGROUP BY m0.id, m0.x, m0.y"
  end

  defrecord Rec, [:x]

  defp fun(x), do: x+x

  test "query interpolation" do
    r = Rec[x: 123]
    query = from(Model) |> select([r], r.x + ^(1 + 2 + 3) + ^r.x) |> normalize
    assert SQL.select(query) == "SELECT (m0.x + 6) + 123\nFROM model AS m0"

    query = from(Model) |> select([r], r.x + ^fun(r.x)) |> normalize
    assert SQL.select(query) == "SELECT m0.x + 246\nFROM model AS m0"
  end

  test "functions" do
    query = from(Model) |> select([], random()) |> normalize
    assert SQL.select(query) == "SELECT random()\nFROM model AS m0"

    query = from(Model) |> select([], round(12.34)) |> normalize
    assert SQL.select(query) == "SELECT round(12.34)\nFROM model AS m0"

    query = from(Model) |> select([], round(12.34, 1)) |> normalize
    assert SQL.select(query) == "SELECT round(12.34, 1)\nFROM model AS m0"

    query = from(Model) |> select([], pow(7, 2)) |> normalize
    assert SQL.select(query) == "SELECT 7 ^ 2\nFROM model AS m0"
  end

  test "join" do
    query = from(Model) |> join(:inner, [p], q in Model2, p.x == q.z) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM model AS m0\nINNER JOIN model2 AS m1 ON m0.x = m1.z"

    query = from(Model) |> join(:inner, [p], q in Model2, p.x == q.z) |> join(:inner, [], Model, true) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM model AS m0\nINNER JOIN model2 AS m1 ON m0.x = m1.z\n" <>
      "INNER JOIN model AS m2 ON TRUE"
  end

  test "join with nothing bound" do
    query = from(Model) |> join(:inner, [], q in Model2, q.z == q.z) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM model AS m0\nINNER JOIN model2 AS m1 ON m1.z = m1.z"
  end

  test "join without entity" do
    query = from("posts") |> join(:inner, [p], q in "comments", p.x == q.z) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM posts AS p0\nINNER JOIN comments AS c0 ON p0.x = c0.z"
  end

  defmodule Comment do
    use Ecto.Model
    queryable "comments" do
      belongs_to :post, Ecto.Adapters.Postgres.SQLTest.Post,
        primary_key: :a,
        foreign_key: :b
    end
  end

  defmodule Post do
    use Ecto.Model
    queryable "posts" do
      has_many :comments, Ecto.Adapters.Postgres.SQLTest.Comment,
        primary_key: :c,
        foreign_key: :d
      has_one :permalink, Ecto.Adapters.Postgres.SQLTest.Permalink,
        primary_key: :e,
        foreign_key: :f
      field :c, :integer
      field :e, :integer
    end
  end

  defmodule Permalink do
    use Ecto.Model
    queryable "permalinks" do
    end
  end

  test "association join belongs_to" do
    query = from(Comment) |> join(:inner, [c], p in c.post) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM comments AS c0\nINNER JOIN posts AS p0 ON p0.a = c0.b"
  end

  test "association join has_many" do
    query = from(Post) |> join(:inner, [p], c in p.comments) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM posts AS p0\nINNER JOIN comments AS c0 ON c0.d = p0.c"
  end

  test "association join has_one" do
    query = from(Post) |> join(:inner, [p], pp in p.permalink) |> select([], 0) |> normalize
    assert SQL.select(query) == "SELECT 0\nFROM posts AS p0\nINNER JOIN permalinks AS p1 ON p1.f = p0.e"
  end

  defmodule PKModel do
    use Ecto.Model

    queryable "model", primary_key: false do
      field :x, :integer
      field :pk, :integer, primary_key: true
      field :y, :integer
    end
  end

  test "primary key any location" do
    model = PKModel.Entity[x: 10, y: 30]
    assert SQL.insert(model) == "INSERT INTO model (x, y)\nVALUES (10, 30)\nRETURNING pk"

    model = PKModel.Entity[x: 10, pk: 20, y: 30]
    assert SQL.insert(model) == "INSERT INTO model (x, pk, y)\nVALUES (10, 20, 30)"
  end

  test "send explicit set primary key" do
    model = Model.Entity[id: 123, x: 0, y: 1]
    assert SQL.insert(model) == "INSERT INTO model (id, x, y)\nVALUES (123, 0, 1)"
  end

  alias Ecto.Migration.Table
  alias Ecto.Migration.Index

  test "executing a string during migration" do
    assert SQL.migrate("example") == "example"
  end

  test "create table" do
    create = {:create, Table.new(name: :posts),
               [{:add, :id, :primary_key, []}],
               [{:add, :title, :string, []}]}
    assert SQL.migrate(create) == "CREATE TABLE posts (id serial primary key, title varchar)"
  end

  test "drop table" do
    drop = {:drop, Table.new(name: :posts)}
    assert SQL.migrate(drop) == "DROP TABLE posts"
  end

  test "create index" do
    create = {:create, Index.new(name: "posts$main", table: :posts, columns: [:category_id, :permalink])}
    assert SQL.migrate(create) == "CREATE INDEX posts$main ON posts (category_id, permalink)"
  end

  test "create index without explicit name" do
    create = {:create, Index.new(table: :posts, columns: [:category_id, :permalink])}
    assert SQL.migrate(create) == "CREATE INDEX posts_category_id_permalink_index ON posts (category_id, permalink)"
  end

  test "create unique index" do
    create = {:create, Index.new(table: :posts, columns: [:permalink], unique: true)}
    assert SQL.migrate(create) == "CREATE UNIQUE INDEX posts_permalink_index ON posts (permalink)"
  end

  test "drop index" do
    drop = {:drop, Index.new(name: "posts$main")}
    assert SQL.migrate(drop) == "DROP INDEX posts$main"
  end

  test "drop index without explicit name" do
    drop = {:drop, Index.new(table: :posts, columns: [:name])}
    assert SQL.migrate(drop) == "DROP INDEX posts_name_index"
  end

  test "alter table" do
    alter = {:alter, Table.new(name: :posts),
               [{:add, :title, :string, []},
                {:modify, :price, :integer, []},
                {:remove, :summary},
                {:rename, :cat_id, :category_id}]}

    assert SQL.migrate(alter) == "ALTER TABLE posts ADD COLUMN title varchar, ALTER COLUMN price TYPE integer, DROP COLUMN summary, RENAME COLUMN cat_id TO category_id"
  end
end
