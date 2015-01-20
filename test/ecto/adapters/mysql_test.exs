defmodule Ecto.Adapters.MySQLTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  alias Ecto.Adapters.MySQL.Connection, as: SQL

  alias Ecto.Queryable
  alias Ecto.Query.Planner
  alias Ecto.Migration.Table
  alias Ecto.Migration.Index
  alias Ecto.Migration.Reference

  defmodule Model do
    use Ecto.Model

    schema "model" do
      field :x, :integer
      field :y, :integer

      has_many :comments, Ecto.Adapters.MySQLTest.Model2,
        references: :x,
        foreign_key: :z
      has_one :permalink, Ecto.Adapters.MySQLTest.Model3,
        references: :y,
        foreign_key: :id
    end
  end

  defmodule Model2 do
    use Ecto.Model

    schema "model2" do
      belongs_to :post, Ecto.Adapters.MySQLTest.Model,
        references: :x,
        foreign_key: :z
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

  defp normalize(query) do
    {query, _params} = Planner.prepare(query, %{})
    Planner.normalize(query, %{}, [])
  end

  test "from" do
    query = Model |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` FROM `model` AS m0}
  end

  test "from without model" do
    query = "posts" |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT p0.`x` FROM `posts` AS p0}
  end

  test "select" do
    query = Model |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x`, m0.`y` FROM `model` AS m0}

    query = Model |> select([r], [r.x, r.y]) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x`, m0.`y` FROM `model` AS m0}
  end

  test "distinct" do
    query = Model |> distinct([r], r.x) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT DISTINCT ON (m0.`x`) m0.`x`, m0.`y` FROM `model` AS m0}

    query = Model |> distinct([r], 2) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT DISTINCT ON (2) m0.`x` FROM `model` AS m0}

    query = Model |> distinct([r], [r.x, r.y]) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT DISTINCT ON (m0.`x`, m0.`y`) m0.`x`, m0.`y` FROM `model` AS m0}
  end

  test "where" do
    query = Model |> where([r], r.x == 42) |> where([r], r.y != 43) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` FROM `model` AS m0 WHERE (m0.`x` = 42) AND (m0.`y` != 43)}
  end

  test "order by" do
    query = Model |> order_by([r], r.x) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` FROM `model` AS m0 ORDER BY m0.`x`}

    query = Model |> order_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` FROM `model` AS m0 ORDER BY m0.`x`, m0.`y`}

    query = Model |> order_by([r], [asc: r.x, desc: r.y]) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` FROM `model` AS m0 ORDER BY m0.`x`, m0.`y` DESC}

    query = Model |> order_by([r], []) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` FROM `model` AS m0}
  end

  test "limit and offset" do
    query = Model |> limit([r], 3) |> select([], 0) |> normalize
    assert SQL.all(query) == ~s{SELECT 0 FROM `model` AS m0 LIMIT 3}

    query = Model |> offset([r], 5) |> select([], 0) |> normalize
    assert SQL.all(query) == ~s{SELECT 0 FROM `model` AS m0 OFFSET 5}

    query = Model |> offset([r], 5) |> limit([r], 3) |> select([], 0) |> normalize
    assert SQL.all(query) == ~s{SELECT 0 FROM `model` AS m0 LIMIT 3 OFFSET 5}
  end

  test "lock" do
    query = Model |> lock(true) |> select([], 0) |> normalize
    assert SQL.all(query) == ~s{SELECT 0 FROM `model` AS m0 FOR UPDATE}

    query = Model |> lock("FOR SHARE NOWAIT") |> select([], 0) |> normalize
    assert SQL.all(query) == ~s{SELECT 0 FROM `model` AS m0 FOR SHARE NOWAIT}
  end

  test "string escape" do
    query = Model |> select([], "'\\  ") |> normalize
    assert SQL.all(query) == ~s{SELECT '''\\  ' FROM `model` AS m0}

    query = Model |> select([], "'") |> normalize
    assert SQL.all(query) == ~s{SELECT '''' FROM `model` AS m0}
  end

  test "binary ops" do
    query = Model |> select([r], r.x == 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` = 2 FROM `model` AS m0}

    query = Model |> select([r], r.x != 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` != 2 FROM `model` AS m0}

    query = Model |> select([r], r.x <= 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` <= 2 FROM `model` AS m0}

    query = Model |> select([r], r.x >= 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` >= 2 FROM `model` AS m0}

    query = Model |> select([r], r.x < 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` < 2 FROM `model` AS m0}

    query = Model |> select([r], r.x > 2) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` > 2 FROM `model` AS m0}
  end

  test "is_nil" do
    query = Model |> select([r], is_nil(r.x)) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` IS NULL FROM `model` AS m0}

    query = Model |> select([r], not is_nil(r.x)) |> normalize
    assert SQL.all(query) == ~s{SELECT NOT (m0.`x` IS NULL) FROM `model` AS m0}
  end

  test "fragments" do
    query = Model |> select([r], fragment("downcase(?)", r.x)) |> normalize
    assert SQL.all(query) == ~s{SELECT downcase(m0.`x`) FROM `model` AS m0}

    value = 13
    query = Model |> select([r], fragment("downcase(?, ?)", r.x, ^value)) |> normalize
    assert SQL.all(query) == ~s{SELECT downcase(m0.`x`, $1) FROM `model` AS m0}
  end

  test "literals" do
    query = Model |> select([], nil) |> normalize
    assert SQL.all(query) == ~s{SELECT NULL FROM `model` AS m0}

    query = Model |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM `model` AS m0}

    query = Model |> select([], false) |> normalize
    assert SQL.all(query) == ~s{SELECT FALSE FROM `model` AS m0}

    query = Model |> select([], "abc") |> normalize
    assert SQL.all(query) == ~s{SELECT 'abc' FROM `model` AS m0}

    query = Model |> select([], <<0, ?a,?b,?c>>) |> normalize
    assert SQL.all(query) == ~s{SELECT '\\x00616263' FROM `model` AS m0}

    query = Model |> select([], uuid(<<0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15>>)) |> normalize
    assert SQL.all(query) == ~s{SELECT '000102030405060708090A0B0C0D0E0F' FROM `model` AS m0}

    query = Model |> select([], uuid("\0\x01\x02\x03\x04\x05\x06\a\b\t\n\v\f\r\x0E\x0F")) |> normalize
    assert SQL.all(query) == ~s{SELECT '000102030405060708090A0B0C0D0E0F' FROM `model` AS m0}

    query = Model |> select([], 123) |> normalize
    assert SQL.all(query) == ~s{SELECT 123 FROM `model` AS m0}

    query = Model |> select([], 123.0) |> normalize
    assert SQL.all(query) == ~s{SELECT 123.0::float FROM `model` AS m0}
  end

  test "nested expressions" do
    z = 123
    query = from(r in Model, []) |> select([r], r.x > 0 and (r.y > ^(-z)) or true) |> normalize
    assert SQL.all(query) == ~s{SELECT ((m0.`x` > 0) AND (m0.`y` > $1)) OR TRUE FROM `model` AS m0}
  end

  test "in expression" do
    query = Model |> select([e], 1 in []) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 = ANY (ARRAY[]) FROM `model` AS m0}

    query = Model |> select([e], 1 in [1,e.x,3]) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 = ANY (ARRAY[1, m0.`x`, 3]) FROM `model` AS m0}
  end

  test "having" do
    query = Model |> having([p], p.x == p.x) |> select([], 0) |> normalize
    assert SQL.all(query) == ~s{SELECT 0 FROM `model` AS m0 HAVING (m0.`x` = m0.`x`)}

    query = Model |> having([p], p.x == p.x) |> having([p], p.y == p.y) |> select([], 0) |> normalize
    assert SQL.all(query) == ~s{SELECT 0 FROM `model` AS m0 HAVING (m0.`x` = m0.`x`) AND (m0.`y` = m0.`y`)}
  end

  test "group by" do
    query = Model |> group_by([r], r.x) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` FROM `model` AS m0 GROUP BY m0.`x`}

    query = Model |> group_by([r], 2) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` FROM `model` AS m0 GROUP BY 2}

    query = Model |> group_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` FROM `model` AS m0 GROUP BY m0.`x`, m0.`y`}

    query = Model |> group_by([r], []) |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` FROM `model` AS m0}
  end

  test "sigils" do
    query = Model |> select([], ~s"abc" in ~w(abc def)) |> normalize
    assert SQL.all(query) == ~s{SELECT 'abc' = ANY (ARRAY['abc', 'def']) FROM `model` AS m0}
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
            |> order_by([], fragment("?", ^3))
            |> order_by([], ^:x)
            |> limit([], ^4)
            |> offset([], ^5)
            |> normalize

    result =
      "SELECT $1 FROM `model` AS m0 INNER JOIN `model2` AS m1 ON $2 " <>
      "INNER JOIN `model2` AS m2 ON $3 WHERE ($4) AND ($5) " <>
      "GROUP BY $6, $7 HAVING ($8) AND ($9) " <>
      "ORDER BY $10, m0.`x` LIMIT $11 OFFSET $12"

    assert SQL.all(query) == String.rstrip(result)
  end

  ## *_all

  test "update all" do
    query = Model |> Queryable.to_query |> normalize
    assert SQL.update_all(query, [x: 0]) ==
           ~s{UPDATE `model` AS m0 SET `x` = 0}

    query = from(e in Model, where: e.x == 123) |> normalize
    assert SQL.update_all(query, [x: 0]) ==
           ~s{UPDATE `model` AS m0 SET `x` = 0 WHERE (m0.`x` = 123)}

    query = Model |> Queryable.to_query |> normalize
    assert SQL.update_all(query, [x: 0, y: "123"]) ==
           ~s{UPDATE `model` AS m0 SET `x` = 0, `y` = '123'}

    query = Model |> Queryable.to_query |> normalize
    assert SQL.update_all(query, [x: quote do: ^0]) ==
           ~s{UPDATE `model` AS m0 SET `x` = $1}
  end

  test "delete all" do
    query = Model |> Queryable.to_query |> normalize
    assert SQL.delete_all(query) == ~s{DELETE FROM `model`}

    query = from(e in Model, where: e.x == 123) |> normalize
    assert SQL.delete_all(query) ==
           ~s{DELETE FROM `model` WHERE (`x` = 123)}
  end

  ## Joins

  test "join" do
    query = Model |> join(:inner, [p], q in Model2, p.x == q.z) |> select([], 0) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT 0 FROM `model` AS m0 INNER JOIN `model2` AS m1 ON m0.`x` = m1.`z`}

    query = Model |> join(:inner, [p], q in Model2, p.x == q.z)
                  |> join(:inner, [], Model, true) |> select([], 0) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT 0 FROM `model` AS m0 INNER JOIN `model2` AS m1 ON m0.`x` = m1.`z` } <>
           ~s{INNER JOIN `model` AS m2 ON TRUE}
  end

  test "join with nothing bound" do
    query = Model |> join(:inner, [], q in Model2, q.z == q.z) |> select([], 0) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT 0 FROM `model` AS m0 INNER JOIN `model2` AS m1 ON m1.`z` = m1.`z`}
  end

  test "join without model" do
    query = "posts" |> join(:inner, [p], q in "comments", p.x == q.z) |> select([], 0) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT 0 FROM `posts` AS p0 INNER JOIN `comments` AS c0 ON p0.`x` = c0.`z`}
  end

  ## Associations

  test "association join belongs_to" do
    query = Model2 |> join(:inner, [c], p in assoc(c, :post)) |> select([], 0) |> normalize
    assert SQL.all(query) ==
           "SELECT 0 FROM `model2` AS m0 INNER JOIN `model` AS m1 ON m1.`x` = m0.`z`"
  end

  test "association join has_many" do
    query = Model |> join(:inner, [p], c in assoc(p, :comments)) |> select([], 0) |> normalize
    assert SQL.all(query) ==
           "SELECT 0 FROM `model` AS m0 INNER JOIN `model2` AS m1 ON m1.`z` = m0.`x`"
  end

  test "association join has_one" do
    query = Model |> join(:inner, [p], pp in assoc(p, :permalink)) |> select([], 0) |> normalize
    assert SQL.all(query) ==
           "SELECT 0 FROM `model` AS m0 INNER JOIN `model3` AS m1 ON m1.`id` = m0.`y`"
  end

  test "join produces correct bindings" do
    query = from(p in Model, join: c in Model2, on: true)
    query = from(p in query, join: c in Model2, on: true, select: {p.id, c.id})
    query = normalize(query)
    assert SQL.all(query) ==
           "SELECT m0.`id`, m2.`id` FROM `model` AS m0 INNER JOIN `model2` AS m1 ON TRUE INNER JOIN `model2` AS m2 ON TRUE"
  end

  # Model based

  test "insert" do
    query = SQL.insert("model", [:x, :y], [])
    assert query == ~s{INSERT INTO `model` (`x`, `y`) VALUES ($1, $2)}

    query = SQL.insert("model", [], [])
    assert query == ~s{INSERT INTO `model` DEFAULT VALUES}
  end

  test "update" do
    query = SQL.update("model", [:id], [:x, :y], [])
    assert query == ~s{UPDATE `model` SET `x` = $2, `y` = $3 WHERE `id` = $1}
  end

  test "delete" do
    query = SQL.delete("model", [:x, :y], [])
    assert query == ~s{DELETE FROM `model` WHERE `x` = $1 AND `y` = $2}
  end

  # DDL

  test "executing a string during migration" do
    assert SQL.execute_ddl("example") == "example"
  end

  test "create table" do
    create = {:create, %Table{name: :posts},
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :title, :string, []},
                {:add, :created_at, :datetime, []}]}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE TABLE `posts` (`id` serial PRIMARY KEY, `title` varchar(255), `created_at` timestamp)|
  end

  test "create table with reference" do
    create = {:create, %Table{name: :posts},
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :category_id, %Reference{table: :categories}, []} ]}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE TABLE `posts` (`id` serial PRIMARY KEY, `category_id` integer REFERENCES `categories`(`id`))|
  end

  test "create table with column options" do
    create = {:create, %Table{name: :posts},
               [{:add, :name, :string, [default: "Untitled", size: 20, null: false]},
                {:add, :price, :numeric, [precision: 8, scale: 2]},
                {:add, :on_hand, :integer, [default: 0, null: true]}]}

    assert SQL.execute_ddl(create) == """
    CREATE TABLE `posts` (`name` varchar(20) DEFAULT 'Untitled' NOT NULL,
    `price` numeric(8,2),
    `on_hand` integer DEFAULT 0 NULL)
    """ |> String.strip |> String.replace("\n", " ")
  end

  test "drop table" do
    drop = {:drop, %Table{name: :posts}}
    assert SQL.execute_ddl(drop) == ~s|DROP TABLE `posts`|
  end

  test "create index" do
    create = {:create, %Index{name: "posts$main", table: :posts, columns: [:category_id, :permalink]}}
    assert SQL.execute_ddl(create) == ~s|CREATE INDEX `posts$main` ON `posts` (`category_id`, `permalink`)|
  end

  test "create unique index" do
    create = {:create, %Index{name: "posts$main", table: :posts, unique: true, columns: [:permalink]}}
    assert SQL.execute_ddl(create) == ~s|CREATE UNIQUE INDEX `posts$main` ON `posts` (`permalink`)|
  end

  test "drop index" do
    drop = {:drop, %Index{name: "posts$main"}}
    assert SQL.execute_ddl(drop) == ~s|DROP INDEX `posts$main`|
  end

  test "alter table" do
    alter = {:alter, %Table{name: :posts},
               [{:add, :title, :string, [default: "Untitled", size: 100, null: false]},
                {:modify, :price, :numeric, [default: 1, null: true, precision: 8, scale: 2]},
                {:remove, :summary}]}

    assert SQL.execute_ddl(alter) == """
    ALTER TABLE `posts`
    ADD COLUMN `title` varchar(100) DEFAULT 'Untitled' NOT NULL,
    ALTER COLUMN `price` TYPE numeric(8,2) DEFAULT 1 NULL,
    DROP COLUMN `summary`
    """ |> String.strip |> String.replace("\n", " ")
  end
end
