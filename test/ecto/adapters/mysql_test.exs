Code.require_file "../../../integration_test/support/types.exs", __DIR__

defmodule Ecto.Adapters.MySQLTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Ecto.Queryable
  alias Ecto.Adapters.MySQL.Connection, as: SQL

  defmodule Model do
    use Ecto.Schema

    schema "model" do
      field :x, :integer
      field :y, :integer
      field :z, :integer

      has_many :comments, Ecto.Adapters.MySQLTest.Model2,
        references: :x,
        foreign_key: :z
      has_one :permalink, Ecto.Adapters.MySQLTest.Model3,
        references: :y,
        foreign_key: :id
    end
  end

  defmodule Model2 do
    use Ecto.Schema

    schema "model2" do
      belongs_to :post, Ecto.Adapters.MySQLTest.Model,
        references: :x,
        foreign_key: :z
    end
  end

  defmodule Model3 do
    use Ecto.Schema

    schema "model3" do
      field :binary, :binary
    end
  end

  defp normalize(query, operation \\ :all) do
    {query, _params, _key} = Ecto.Query.Planner.prepare(query, operation, Ecto.Adapters.MySQL)
    Ecto.Query.Planner.normalize(query, operation, Ecto.Adapters.MySQL)
  end

  test "from" do
    query = Model |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` FROM `model` AS m0}
  end

  test "from without model" do
    query = "posts" |> select([r], r.x) |> normalize
    assert SQL.all(query) == ~s{SELECT p0.`x` FROM `posts` AS p0}

    assert_raise Ecto.QueryError, ~r"MySQL requires a schema module", fn ->
      SQL.all from(p in "posts", select: p) |> normalize()
    end
  end

  test "select" do
    query = Model |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x`, m0.`y` FROM `model` AS m0}

    query = Model |> select([r], [r.x, r.y]) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x`, m0.`y` FROM `model` AS m0}

    query = Model |> select([r], take(r, [:x, :y])) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x`, m0.`y` FROM `model` AS m0}
  end

  test "distinct" do
    query = Model |> distinct([r], true) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT DISTINCT m0.`x`, m0.`y` FROM `model` AS m0}

    query = Model |> distinct([r], false) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x`, m0.`y` FROM `model` AS m0}

    query = Model |> distinct(true) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT DISTINCT m0.`x`, m0.`y` FROM `model` AS m0}

    query = Model |> distinct(false) |> select([r], {r.x, r.y}) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x`, m0.`y` FROM `model` AS m0}

    assert_raise Ecto.QueryError, ~r"DISTINCT with multiple columns is not supported by MySQL", fn ->
      query = Model |> distinct([r], [r.x, r.y]) |> select([r], {r.x, r.y}) |> normalize
      SQL.all(query)
    end
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
    query = Model |> limit([r], 3) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM `model` AS m0 LIMIT 3}

    query = Model |> offset([r], 5) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM `model` AS m0 OFFSET 5}

    query = Model |> offset([r], 5) |> limit([r], 3) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM `model` AS m0 LIMIT 3 OFFSET 5}
  end

  test "lock" do
    query = Model |> lock("LOCK IN SHARE MODE") |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM `model` AS m0 LOCK IN SHARE MODE}
  end

  test "string escape" do
    query = "model" |> where(foo: "'\\  ") |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM `model` AS m0 WHERE (m0.`foo` = '''\\\\  ')}

    query = "model" |> where(foo: "'") |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM `model` AS m0 WHERE (m0.`foo` = '''')}
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
    query = Model |> select([r], fragment("lcase(?)", r.x)) |> normalize
    assert SQL.all(query) == ~s{SELECT lcase(m0.`x`) FROM `model` AS m0}

    query = Model |> select([r], r.x) |> where([], fragment("? = \"query\\?\"", ^10)) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` FROM `model` AS m0 WHERE (? = \"query?\")}

    value = 13
    query = Model |> select([r], fragment("lcase(?, ?)", r.x, ^value)) |> normalize
    assert SQL.all(query) == ~s{SELECT lcase(m0.`x`, ?) FROM `model` AS m0}

    query = Model |> select([], fragment(title: 2)) |> normalize
    assert_raise Ecto.QueryError, fn ->
      SQL.all(query)
    end
  end

  test "literals" do
    query = "model" |> where(foo: true) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM `model` AS m0 WHERE (m0.`foo` = TRUE)}

    query = "model" |> where(foo: false) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM `model` AS m0 WHERE (m0.`foo` = FALSE)}

    query = "model" |> where(foo: "abc") |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM `model` AS m0 WHERE (m0.`foo` = 'abc')}

    query = "model" |> where(foo: 123) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM `model` AS m0 WHERE (m0.`foo` = 123)}

    query = "model" |> where(foo: 123.0) |> select([], true) |> normalize
    assert SQL.all(query) == ~s{SELECT TRUE FROM `model` AS m0 WHERE (m0.`foo` = (0 + 123.0))}
  end

  test "tagged type" do
    query = Model |> select([], type(^"601d74e4-a8d3-4b6e-8365-eddb4c893327", Ecto.UUID)) |> normalize
    assert SQL.all(query) == ~s{SELECT CAST(? AS binary(16)) FROM `model` AS m0}
  end

  test "nested expressions" do
    z = 123
    query = from(r in Model, []) |> select([r], r.x > 0 and (r.y > ^(-z)) or true) |> normalize
    assert SQL.all(query) == ~s{SELECT ((m0.`x` > 0) AND (m0.`y` > ?)) OR TRUE FROM `model` AS m0}
  end

  test "in expression" do
    query = Model |> select([e], 1 in []) |> normalize
    assert SQL.all(query) == ~s{SELECT false FROM `model` AS m0}

    query = Model |> select([e], 1 in [1,e.x,3]) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 IN (1,m0.`x`,3) FROM `model` AS m0}

    query = Model |> select([e], 1 in ^[]) |> normalize
    assert SQL.all(query) == ~s{SELECT false FROM `model` AS m0}

    query = Model |> select([e], 1 in ^[1, 2, 3]) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 IN (?,?,?) FROM `model` AS m0}

    query = Model |> select([e], 1 in [1, ^2, 3]) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 IN (1,?,3) FROM `model` AS m0}

    query = Model |> select([e], 1 in fragment("foo")) |> normalize
    assert SQL.all(query) == ~s{SELECT 1 = ANY(foo) FROM `model` AS m0}
  end

  test "having" do
    query = Model |> having([p], p.x == p.x) |> select([p], p.x) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`x` FROM `model` AS m0 HAVING (m0.`x` = m0.`x`)}

    query = Model |> having([p], p.x == p.x) |> having([p], p.y == p.y) |> select([p], [p.y, p.x]) |> normalize
    assert SQL.all(query) == ~s{SELECT m0.`y`, m0.`x` FROM `model` AS m0 HAVING (m0.`x` = m0.`x`) AND (m0.`y` = m0.`y`)}
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

  test "interpolated values" do
    query = Model
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
      "SELECT ? FROM `model` AS m0 INNER JOIN `model2` AS m1 ON ? " <>
      "INNER JOIN `model2` AS m2 ON ? WHERE (?) AND (?) " <>
      "GROUP BY ?, ? HAVING (?) AND (?) " <>
      "ORDER BY ?, m0.`x` LIMIT ? OFFSET ?"

    assert SQL.all(query) == String.rstrip(result)
  end

  ## *_all

  test "update all" do
    query = from(m in Model, update: [set: [x: 0]]) |> normalize(:update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE `model` AS m0 SET `x` = 0}

    query = from(m in Model, update: [set: [x: 0], inc: [y: 1, z: -3]]) |> normalize(:update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE `model` AS m0 SET `x` = 0, `y` = `y` + 1, `z` = `z` + -3}

    query = from(e in Model, where: e.x == 123, update: [set: [x: 0]]) |> normalize(:update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE `model` AS m0 SET `x` = 0 WHERE (m0.`x` = 123)}

    query = from(m in Model, update: [set: [x: 0, y: "123"]]) |> normalize(:update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE `model` AS m0 SET `x` = 0, `y` = 123}

    query = from(m in Model, update: [set: [x: ^0]]) |> normalize(:update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE `model` AS m0 SET `x` = ?}

    query = Model |> join(:inner, [p], q in Model2, p.x == q.z)
                  |> update([_], set: [x: 0]) |> normalize(:update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE `model` AS m0 INNER JOIN `model2` AS m1 ON m0.`x` = m1.`z` SET `x` = 0}

    query = from(e in Model, where: e.x == 123, update: [set: [x: 0]],
                             join: q in Model2, on: e.x == q.z) |> normalize(:update_all)
    assert SQL.update_all(query) ==
           ~s{UPDATE `model` AS m0 INNER JOIN `model2` AS m1 ON m0.`x` = m1.`z` } <>
           ~s{SET `x` = 0 WHERE (m0.`x` = 123)}
  end

  test "update all with prefix" do
    query = from(m in Model, update: [set: [x: 0]]) |> normalize(:update_all)
    assert SQL.update_all(%{query | prefix: "prefix"}) ==
           ~s{UPDATE `prefix`.`model` AS m0 SET `x` = 0}
  end

  test "delete all" do
    query = Model |> Queryable.to_query |> normalize
    assert SQL.delete_all(query) == ~s{DELETE m0.* FROM `model` AS m0}

    query = from(e in Model, where: e.x == 123) |> normalize
    assert SQL.delete_all(query) ==
           ~s{DELETE m0.* FROM `model` AS m0 WHERE (m0.`x` = 123)}

    query = Model |> join(:inner, [p], q in Model2, p.x == q.z) |> normalize
    assert SQL.delete_all(query) ==
           ~s{DELETE m0.* FROM `model` AS m0 INNER JOIN `model2` AS m1 ON m0.`x` = m1.`z`}

    query = from(e in Model, where: e.x == 123, join: q in Model2, on: e.x == q.z) |> normalize
    assert SQL.delete_all(query) ==
           ~s{DELETE m0.* FROM `model` AS m0 } <>
           ~s{INNER JOIN `model2` AS m1 ON m0.`x` = m1.`z` WHERE (m0.`x` = 123)}
  end

  test "delete all with prefix" do
    query = Model |> Queryable.to_query |> normalize
    assert SQL.delete_all(%{query | prefix: "prefix"}) == ~s{DELETE m0.* FROM `prefix`.`model` AS m0}
  end

  ## Joins

  test "join" do
    query = Model |> join(:inner, [p], q in Model2, p.x == q.z) |> select([], true) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT TRUE FROM `model` AS m0 INNER JOIN `model2` AS m1 ON m0.`x` = m1.`z`}

    query = Model |> join(:inner, [p], q in Model2, p.x == q.z)
                  |> join(:inner, [], Model, true) |> select([], true) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT TRUE FROM `model` AS m0 INNER JOIN `model2` AS m1 ON m0.`x` = m1.`z` } <>
           ~s{INNER JOIN `model` AS m2 ON TRUE}
  end

  test "join with nothing bound" do
    query = Model |> join(:inner, [], q in Model2, q.z == q.z) |> select([], true) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT TRUE FROM `model` AS m0 INNER JOIN `model2` AS m1 ON m1.`z` = m1.`z`}
  end

  test "join without model" do
    query = "posts" |> join(:inner, [p], q in "comments", p.x == q.z) |> select([], true) |> normalize
    assert SQL.all(query) ==
           ~s{SELECT TRUE FROM `posts` AS p0 INNER JOIN `comments` AS c1 ON p0.`x` = c1.`z`}
  end

  test "join with prefix" do
    query = Model |> join(:inner, [p], q in Model2, p.x == q.z) |> select([], true) |> normalize
    assert SQL.all(%{query | prefix: "prefix"}) ==
           ~s{SELECT TRUE FROM `prefix`.`model` AS m0 INNER JOIN `prefix`.`model2` AS m1 ON m0.`x` = m1.`z`}
  end

  test "join with fragment" do
    query = Model
            |> join(:inner, [p], q in fragment("SELECT * FROM model2 AS m2 WHERE m2.id = ? AND m2.field = ?", p.x, ^10))
            |> select([p], {p.id, ^0})
            |> where([p], p.id > 0 and p.id < ^100)
            |> normalize
    assert SQL.all(query) ==
           ~s{SELECT m0.`id`, ? FROM `model` AS m0 INNER JOIN } <>
           ~s{(SELECT * FROM model2 AS m2 WHERE m2.id = m0.`x` AND m2.field = ?) AS f1 ON TRUE } <>
           ~s{WHERE ((m0.`id` > 0) AND (m0.`id` < ?))}
  end

  test "join with fragment and on defined" do
    query = Model
            |> join(:inner, [p], q in fragment("SELECT * FROM model2"), q.id == p.id)
            |> select([p], {p.id, ^0})
            |> normalize
    assert SQL.all(query) ==
           ~s{SELECT m0.`id`, ? FROM `model` AS m0 INNER JOIN } <>
           ~s{(SELECT * FROM model2) AS f1 ON f1.`id` = m0.`id`}
  end

  ## Associations

  test "association join belongs_to" do
    query = Model2 |> join(:inner, [c], p in assoc(c, :post)) |> select([], true) |> normalize
    assert SQL.all(query) ==
           "SELECT TRUE FROM `model2` AS m0 INNER JOIN `model` AS m1 ON m1.`x` = m0.`z`"
  end

  test "association join has_many" do
    query = Model |> join(:inner, [p], c in assoc(p, :comments)) |> select([], true) |> normalize
    assert SQL.all(query) ==
           "SELECT TRUE FROM `model` AS m0 INNER JOIN `model2` AS m1 ON m1.`z` = m0.`x`"
  end

  test "association join has_one" do
    query = Model |> join(:inner, [p], pp in assoc(p, :permalink)) |> select([], true) |> normalize
    assert SQL.all(query) ==
           "SELECT TRUE FROM `model` AS m0 INNER JOIN `model3` AS m1 ON m1.`id` = m0.`y`"
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
    query = SQL.insert(nil, "model", [:x, :y], [[:x, :y]], [])
    assert query == ~s{INSERT INTO `model` (`x`,`y`) VALUES (?,?)}

    query = SQL.insert(nil, "model", [:x, :y], [[:x, :y], [nil, :y]], [])
    assert query == ~s{INSERT INTO `model` (`x`,`y`) VALUES (?,?),(DEFAULT,?)}

    query = SQL.insert(nil, "model", [], [[]], [])
    assert query == ~s{INSERT INTO `model` () VALUES ()}

    query = SQL.insert("prefix", "model", [], [[]], [])
    assert query == ~s{INSERT INTO `prefix`.`model` () VALUES ()}
  end

  test "update" do
    query = SQL.update(nil, "model", [:id], [:x, :y], [])
    assert query == ~s{UPDATE `model` SET `id` = ? WHERE `x` = ? AND `y` = ?}

    query = SQL.update("prefix", "model", [:id], [:x, :y], [])
    assert query == ~s{UPDATE `prefix`.`model` SET `id` = ? WHERE `x` = ? AND `y` = ?}
  end

  test "delete" do
    query = SQL.delete(nil, "model", [:x, :y], [])
    assert query == ~s{DELETE FROM `model` WHERE `x` = ? AND `y` = ?}

    query = SQL.delete("prefix", "model", [:x, :y], [])
    assert query == ~s{DELETE FROM `prefix`.`model` WHERE `x` = ? AND `y` = ?}
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
                {:add, :is_active, :boolean, [default: true]}]}

    assert SQL.execute_ddl(create) == """
    CREATE TABLE `posts` (`name` varchar(20) DEFAULT 'Untitled' NOT NULL,
    `price` numeric(8,2) DEFAULT expr,
    `on_hand` integer DEFAULT 0 NULL,
    `is_active` boolean DEFAULT true) ENGINE = INNODB
    """ |> remove_newlines
  end

  test "create table with prefix" do
    create = {:create, table(:posts, prefix: :foo),
               [{:add, :category_0, references(:categories, prefix: :foo), []}]}

    assert SQL.execute_ddl(create) == """
    CREATE TABLE `foo`.`posts` (`category_0` BIGINT UNSIGNED ,
    CONSTRAINT `posts_category_0_fkey` FOREIGN KEY (`category_0`) REFERENCES `foo`.`categories`(`id`)) ENGINE = INNODB
    """ |> remove_newlines
  end

  test "create table with engine" do
    create = {:create, table(:posts, engine: :myisam),
               [{:add, :id, :serial, [primary_key: true]}]}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE TABLE `posts` (`id` serial , PRIMARY KEY(`id`)) ENGINE = MYISAM|
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
    CREATE TABLE `posts` (`id` serial , PRIMARY KEY(`id`),
    `category_0` BIGINT UNSIGNED ,
    CONSTRAINT `posts_category_0_fkey` FOREIGN KEY (`category_0`) REFERENCES `categories`(`id`),
    `category_1` BIGINT UNSIGNED ,
    CONSTRAINT `foo_bar` FOREIGN KEY (`category_1`) REFERENCES `categories`(`id`),
    `category_2` BIGINT UNSIGNED ,
    CONSTRAINT `posts_category_2_fkey` FOREIGN KEY (`category_2`) REFERENCES `categories`(`id`),
    `category_3` BIGINT UNSIGNED NOT NULL ,
    CONSTRAINT `posts_category_3_fkey` FOREIGN KEY (`category_3`) REFERENCES `categories`(`id`) ON DELETE CASCADE,
    `category_4` BIGINT UNSIGNED ,
    CONSTRAINT `posts_category_4_fkey` FOREIGN KEY (`category_4`) REFERENCES `categories`(`id`) ON DELETE SET NULL) ENGINE = INNODB
    """ |> remove_newlines
  end

  test "create table with options" do
    create = {:create, table(:posts, options: "WITH FOO=BAR"),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :created_at, :datetime, []}]}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE TABLE `posts` (`id` serial , PRIMARY KEY(`id`), `created_at` datetime) ENGINE = INNODB WITH FOO=BAR|
  end

  test "create table with both engine and options" do
    create = {:create, table(:posts, engine: :myisam, options: "WITH FOO=BAR"),
               [{:add, :id, :serial, [primary_key: true]},
                {:add, :created_at, :datetime, []}]}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE TABLE `posts` (`id` serial , PRIMARY KEY(`id`), `created_at` datetime) ENGINE = MYISAM WITH FOO=BAR|
  end

  test "drop table" do
    drop = {:drop, table(:posts)}
    assert SQL.execute_ddl(drop) == ~s|DROP TABLE `posts`|
  end

  test "drop table with prefixes" do
    drop = {:drop, table(:posts, prefix: :foo)}
    assert SQL.execute_ddl(drop) == ~s|DROP TABLE `foo`.`posts`|
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
    ALTER TABLE `posts` ADD `title` varchar(100) DEFAULT 'Untitled' NOT NULL,
    ADD `author_id` BIGINT UNSIGNED ,
    ADD CONSTRAINT `posts_author_id_fkey` FOREIGN KEY (`author_id`) REFERENCES `author`(`id`),
    MODIFY `price` numeric(8,2) NULL, MODIFY `cost` integer DEFAULT NULL NOT NULL,
    MODIFY `permalink_id` BIGINT UNSIGNED NOT NULL ,
    ADD CONSTRAINT `posts_permalink_id_fkey` FOREIGN KEY (`permalink_id`) REFERENCES `permalinks`(`id`),
    DROP `summary`
    """ |> remove_newlines
  end

  test "alter table with prefix" do
    alter = {:alter, table(:posts, prefix: :foo),
               [{:add, :author_id, references(:author), []},
                {:modify, :permalink_id, references(:permalinks), null: false}]}

    assert SQL.execute_ddl(alter) == """
    ALTER TABLE `foo`.`posts` ADD `author_id` BIGINT UNSIGNED ,
    ADD CONSTRAINT `posts_author_id_fkey` FOREIGN KEY (`author_id`) REFERENCES `foo`.`author`(`id`),
    MODIFY `permalink_id` BIGINT UNSIGNED NOT NULL ,
    ADD CONSTRAINT `posts_permalink_id_fkey` FOREIGN KEY (`permalink_id`) REFERENCES `foo`.`permalinks`(`id`)
    """ |> remove_newlines
  end

  test "create index" do
    create = {:create, index(:posts, [:category_id, :permalink])}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE INDEX `posts_category_id_permalink_index` ON `posts` (`category_id`, `permalink`)|

    create = {:create, index(:posts, ["lower(permalink)"], name: "posts$main")}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE INDEX `posts$main` ON `posts` (`lower(permalink)`)|
  end

  test "create index with prefix" do
    create = {:create, index(:posts, [:category_id, :permalink], prefix: :foo)}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE INDEX `posts_category_id_permalink_index` ON `foo`.`posts` (`category_id`, `permalink`)|
  end

  test "create index asserting concurrency" do
    create = {:create, index(:posts, ["lower(permalink)"], name: "posts$main", concurrently: true)}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE INDEX `posts$main` ON `posts` (`lower(permalink)`) LOCK=NONE|
  end

  test "create unique index" do
    create = {:create, index(:posts, [:permalink], unique: true)}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE UNIQUE INDEX `posts_permalink_index` ON `posts` (`permalink`)|
  end

  test "create unique index with condition" do
    assert_raise ArgumentError, "MySQL adapter does not where in indexes", fn ->
      create = {:create, index(:posts, [:permalink], unique: true, where: "public IS TRUE")}
      SQL.execute_ddl(create)
    end
  end

  test "create an index using a different type" do
    create = {:create, index(:posts, [:permalink], using: :hash)}
    assert SQL.execute_ddl(create) ==
           ~s|CREATE INDEX `posts_permalink_index` ON `posts` (`permalink`) USING hash|
  end

  test "drop index" do
    drop = {:drop, index(:posts, [:id], name: "posts$main")}
    assert SQL.execute_ddl(drop) == ~s|DROP INDEX `posts$main` ON `posts`|
  end

  test "drop index with prefix" do
    drop = {:drop, index(:posts, [:id], name: "posts$main", prefix: :foo)}
    assert SQL.execute_ddl(drop) == ~s|DROP INDEX `posts$main` ON `foo`.`posts`|
  end

  test "drop index asserting concurrency" do
    drop = {:drop, index(:posts, [:id], name: "posts$main", concurrently: true)}
    assert SQL.execute_ddl(drop) == ~s|DROP INDEX `posts$main` ON `posts` LOCK=NONE|
  end

  test "rename table" do
    rename = {:rename, table(:posts), table(:new_posts)}
    assert SQL.execute_ddl(rename) == ~s|RENAME TABLE `posts` TO `new_posts`|
  end

  test "rename table with prefix" do
    rename = {:rename, table(:posts, prefix: :foo), table(:new_posts, prefix: :foo)}
    assert SQL.execute_ddl(rename) == ~s|RENAME TABLE `foo`.`posts` TO `foo`.`new_posts`|
  end

  test "rename column" do
    rename = {:rename, table(:posts), :given_name, :first_name}
    assert SQL.execute_ddl(rename) ==
      [
        "SELECT @column_type := COLUMN_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'posts' AND COLUMN_NAME = 'given_name' LIMIT 1",
        "SET @rename_stmt = concat('ALTER TABLE `posts` CHANGE COLUMN `given_name` `first_name` ', @column_type)",
        "PREPARE rename_stmt FROM @rename_stmt",
        "EXECUTE rename_stmt"
      ]
  end

  test "rename column in table with prefixes" do
    rename = {:rename, table(:posts, prefix: :foo), :given_name, :first_name}
    assert SQL.execute_ddl(rename) ==
      [
        "SELECT @column_type := COLUMN_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'posts' AND COLUMN_NAME = 'given_name' LIMIT 1",
        "SET @rename_stmt = concat('ALTER TABLE `foo`.`posts` CHANGE COLUMN `given_name` `first_name` ', @column_type)",
        "PREPARE rename_stmt FROM @rename_stmt",
        "EXECUTE rename_stmt"
      ]
  end

  # Unsupported types and clauses

  test "arrays" do
    assert_raise Ecto.QueryError, ~r"Array type is not supported by MySQL", fn ->
      query = Model |> select([], fragment("?", [1, 2, 3])) |> normalize
      SQL.all(query)
    end
  end

  defp remove_newlines(string) do
    string |> String.strip |> String.replace("\n", " ")
  end
end
