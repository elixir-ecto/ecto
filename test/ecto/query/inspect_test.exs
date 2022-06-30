defmodule Inspect.Post do
  use Ecto.Schema

  schema "posts" do
    field :visits, :integer
    has_many :comments, Inspect.Comment
    has_one :post, Inspect.Post
  end
end

defmodule Inspect.Comment do
  use Ecto.Schema

  schema "comments" do
  end
end

defmodule Ecto.Query.InspectTest do
  use ExUnit.Case, async: true
  import Ecto.Query

  alias Inspect.Post
  alias Inspect.Comment

  test "dynamic" do
    assert inspect(dynamic([p], p.foo == true)) ==
           "dynamic([p], p.foo == true)"

    assert inspect(dynamic([p], p.foo == ^"hello")) ==
           "dynamic([p], p.foo == ^\"hello\")"

    assert inspect(dynamic([p, c], p.foo == c.bar)) ==
           "dynamic([p, c], p.foo == c.bar)"

    assert inspect(dynamic([p, ..., c], p.foo == c.bar)) ==
           "dynamic([p, ..., c], p.foo == c.bar)"

    assert inspect(dynamic([a, b, ..., c, d], a.foo == b.bar and c.foo == d.bar)) ==
           "dynamic([a, b, ..., c, d], a.foo == b.bar and c.foo == d.bar)"

    assert inspect(dynamic([comments: c], c.bar == ^1)) ==
           "dynamic([comments: c], c.bar == ^1)"

    dynamic = dynamic([p], p.bar == ^1)
    assert inspect(dynamic([p], ^dynamic and p.foo == ^0)) ==
           "dynamic([p], p.bar == ^1 and p.foo == ^0)"

    dynamic = dynamic([o, b], b.user_id == ^1 or ^false)
    assert inspect(dynamic([o], o.type == ^2 and ^dynamic)) ==
           "dynamic([o, b], o.type == ^2 and (b.user_id == ^1 or ^false))"

    sq = from(Post, [])
    dynamic = dynamic([o, b], b.user_id == ^1 or b.user_id in subquery(sq))
    assert inspect(dynamic([o], o.type == ^2 and ^dynamic)) ==
           "dynamic([o, b], o.type == ^2 and (b.user_id == ^1 or b.user_id in subquery(#Ecto.Query<from p0 in Inspect.Post>)))"
  end

  test "invalid query" do
    assert i(select("posts", [a, b], {a.foo, b.bar})) ==
           "from p0 in \"posts\", select: {p0.foo, unknown_binding_1!.bar}"
  end

  test "from" do
    assert i(from(Post, [])) ==
           ~s{from p0 in Inspect.Post}

    assert i(from(x in Post, [])) ==
          ~s{from p0 in Inspect.Post}

    assert i(from(x in "posts", [])) ==
           ~s{from p0 in "posts"}

    assert i(from(x in {"user_posts", Post}, [])) ==
           ~s[from p0 in {"user_posts", Inspect.Post}]

    assert i(from(subquery(Post), [])) ==
           ~s{from p0 in subquery(from p0 in Inspect.Post)}
  end

  test "CTE" do
    initial_query =
      "categories"
      |> where([c], is_nil(c.parent_id))
      |> select([c], %{id: c.id, depth: fragment("1")})

    iteration_query =
      "categories"
      |> join(:inner, [c], t in "tree", on: t.id == c.parent_id)
      |> select([c, t], %{id: c.id, depth: fragment("? + 1", t.depth)})

    cte_query = initial_query |> union_all(^iteration_query)

    query =
      "products"
      |> recursive_ctes(true)
      |> with_cte("tree", as: ^cte_query)
      |> join(:inner, [r], t in "tree", on: t.id == r.category_id)

    assert query |> inspect() |> Inspect.Algebra.format(80) |> to_string() ==
      ~s{#Ecto.Query<from p0 in "products", join: t1 in "tree", on: t1.id == p0.category_id>\n} <>
      ~s{|> recursive_ctes(true)\n} <>
      ~s{|> with_cte("tree", as: } <>
      ~s{#Ecto.Query<from c0 in "categories", } <>
      ~s{where: is_nil(c0.parent_id), } <>
      ~s{union_all: (from c0 in "categories",\n  } <>
      ~s{join: t1 in "tree",\n  } <>
      ~s{on: t1.id == c0.parent_id,\n  } <>
      ~s{select: %\{id: c0.id, depth: fragment("? + 1", t1.depth)\}), } <>
      ~s{select: %\{id: c0.id, depth: fragment("1")\}>)}
  end

  test "cte with fragments" do
    assert with_cte("foo", "foo", as: fragment("select 1 as bar"))
           |> inspect() |> Inspect.Algebra.format(80) |> to_string() ==
      ~s{#Ecto.Query<from f0 in "foo">\n} <>
      ~s{|> with_cte("foo", as: fragment("select 1 as bar"))}
  end

  test "join" do
    assert i(from(x in Post, join: y in Comment)) ==
           ~s{from p0 in Inspect.Post, join: c1 in Inspect.Comment, on: true}

    assert i(from(x in Post, join: y in Comment, on: x.id == y.id)) ==
           ~s{from p0 in Inspect.Post, join: c1 in Inspect.Comment, on: p0.id == c1.id}

    assert i(from(x in Post, full_join: y in Comment, on: x.id == y.id)) ==
           ~s{from p0 in Inspect.Post, full_join: c1 in Inspect.Comment, on: p0.id == c1.id}

    assert i(from(x in Post, full_join: y in {"user_comments", Comment}, on: x.id == y.id)) ==
           ~s[from p0 in Inspect.Post, full_join: c1 in {"user_comments", Inspect.Comment}, on: p0.id == c1.id]

    assert i(from(x in Post, left_join: y in assoc(x, :comments))) ==
           ~s{from p0 in Inspect.Post, left_join: c1 in assoc(p0, :comments)}

    assert i(from(x in Post, left_join: y in assoc(x, :comments), on: y.published == true)) ==
           ~s{from p0 in Inspect.Post, left_join: c1 in assoc(p0, :comments), on: c1.published == true}

    assert i(from(x in Post, right_join: y in assoc(x, :post), join: z in assoc(y, :post))) ==
           ~s{from p0 in Inspect.Post, right_join: p1 in assoc(p0, :post), join: p2 in assoc(p1, :post)}

    assert i(from(x in Post, inner_join: y in fragment("foo ? and ?", x.id, ^1), on: y.id == x.id)) ==
           ~s{from p0 in Inspect.Post, join: f1 in fragment("foo ? and ?", p0.id, ^1), on: f1.id == p0.id}

    assert i(from(x in Post, join: y in subquery(Comment), on: x.id == y.id)) ==
           ~s{from p0 in Inspect.Post, join: c1 in subquery(from c0 in Inspect.Comment), on: p0.id == c1.id}

    assert i(from(x in Post, join: y in ^from(c in Comment, where: true), on: x.id == y.id)) ==
           ~s{from p0 in Inspect.Post, join: c1 in ^#Ecto.Query<from c0 in Inspect.Comment, where: true>, on: p0.id == c1.id}
  end

  test "as" do
    assert i(from(x in Post, as: :post)) ==
      ~s{from p0 in Inspect.Post, as: :post}

    assert i(from(x in Post, join: y in Comment, as: :comment, on: x.id == y.id)) ==
      ~s{from p0 in Inspect.Post, join: c1 in Inspect.Comment, as: :comment, on: p0.id == c1.id}

    assert i(from(x in Post, inner_join: y in fragment("foo ? and ?", x.id, ^1), as: :foo, on: y.id == x.id)) ==
      ~s{from p0 in Inspect.Post, join: f1 in fragment("foo ? and ?", p0.id, ^1), as: :foo, on: f1.id == p0.id}

    assert i(from(x in Post, join: y in subquery(Comment), as: :comment, on: x.id == y.id)) ==
      ~s{from p0 in Inspect.Post, join: c1 in subquery(from c0 in Inspect.Comment), as: :comment, on: p0.id == c1.id}
  end

  test "prefix" do
    assert i(from(x in Post, prefix: "post")) ==
      ~s{from p0 in Inspect.Post, prefix: "post"}

    assert i(from(x in Post, join: y in Comment, prefix: "comment", on: x.id == y.id)) ==
      ~s{from p0 in Inspect.Post, join: c1 in Inspect.Comment, prefix: "comment", on: p0.id == c1.id}

    assert i(from(x in Post, inner_join: y in fragment("foo ? and ?", x.id, ^1), prefix: "foo", on: y.id == x.id)) ==
      ~s{from p0 in Inspect.Post, join: f1 in fragment("foo ? and ?", p0.id, ^1), prefix: "foo", on: f1.id == p0.id}

    assert i(from(x in Post, join: y in subquery(Comment), prefix: "comment", on: x.id == y.id)) ==
      ~s{from p0 in Inspect.Post, join: c1 in subquery(from c0 in Inspect.Comment), prefix: "comment", on: p0.id == c1.id}
  end

  test "where" do
    assert i(from(x in Post, where: x.foo == x.bar, where: true)) ==
           ~s{from p0 in Inspect.Post, where: p0.foo == p0.bar, where: true}
  end

  test "where in subquery" do
    s = from(x in Post, where: x.bar == ^"1", select: x.foo)
    assert i(from(x in Post, where: x.foo in subquery(s))) ==
          ~s{from p0 in Inspect.Post, where: p0.foo in subquery(#Ecto.Query<from p0 in Inspect.Post, where: p0.bar == ^"1", select: p0.foo>)}
  end

  test "group by" do
    assert i(from(x in Post, group_by: [x.foo, x.bar], group_by: x.foobar)) ==
           ~s{from p0 in Inspect.Post, group_by: [p0.foo, p0.bar], group_by: [p0.foobar]}
  end

  test "having" do
    assert i(from(x in Post, having: x.foo == x.bar, having: true)) ==
           ~s{from p0 in Inspect.Post, having: p0.foo == p0.bar, having: true}
  end

  test "window" do
    assert i(from(x in Post, windows: [a: [partition_by: x.foo]])) ==
           "from p0 in Inspect.Post, windows: [a: [partition_by: [p0.foo]]]"

    assert i(from(x in Post, windows: [a: [partition_by: x.foo], b: [partition_by: x.bar]])) ==
           "from p0 in Inspect.Post, windows: [a: [partition_by: [p0.foo]]], windows: [b: [partition_by: [p0.bar]]]"

    assert i(from(x in Post, windows: [a: [partition_by: x.foo]], windows: [b: [partition_by: x.bar]])) ==
           "from p0 in Inspect.Post, windows: [a: [partition_by: [p0.foo]]], windows: [b: [partition_by: [p0.bar]]]"

    assert i(from(x in Post, windows: [a: [partition_by: [x.foo, x.bar]]])) ==
           "from p0 in Inspect.Post, windows: [a: [partition_by: [p0.foo, p0.bar]]]"
  end

  test "over" do
    assert i(from(x in Post, select: count(x.x) |> over(:x))) ==
           "from p0 in Inspect.Post, select: over(count(p0.x), :x)"

    assert i(from(x in Post, select: count(x.x) |> over)) ==
           ~s{from p0 in Inspect.Post, select: over(count(p0.x), [])}

    assert i(from(x in Post, select: count(x.x) |> over(partition_by: x.bar))) ==
           ~s{from p0 in Inspect.Post, select: over(count(p0.x), partition_by: [p0.bar])}
  end

  test "order by" do
    assert i(from(x in Post, order_by: [asc: x.foo, desc: x.bar], order_by: x.foobar)) ==
           ~s{from p0 in Inspect.Post, order_by: [asc: p0.foo, desc: p0.bar], order_by: [asc: p0.foobar]}
  end

  test "union" do
    assert i(from(x in Post, union: ^from(y in Post), union_all: ^from(z in Post))) ==
             ~s{from p0 in Inspect.Post, union: (from p0 in Inspect.Post), union_all: (from p0 in Inspect.Post)}
  end

  test "except" do
    assert i(from(x in Post, except: ^from(y in Post), except_all: ^from(y in Post))) ==
             ~s{from p0 in Inspect.Post, except: (from p0 in Inspect.Post), except_all: (from p0 in Inspect.Post)}
  end

  test "intersect" do
    assert i(from(x in Post, intersect: ^from(y in Post), intersect_all: ^from(y in Post))) ==
             ~s{from p0 in Inspect.Post, intersect: (from p0 in Inspect.Post), intersect_all: (from p0 in Inspect.Post)}
  end

  test "limit" do
    assert i(from(x in Post, limit: 123)) ==
           ~s{from p0 in Inspect.Post, limit: 123}
  end

  test "offset" do
    assert i(from(x in Post, offset: 123)) ==
           ~s{from p0 in Inspect.Post, offset: 123}
  end

  test "distinct" do
    assert i(from(x in Post, distinct: true)) ==
           ~s{from p0 in Inspect.Post, distinct: true}

    assert i(from(x in Post, distinct: [x.foo])) ==
           ~s{from p0 in Inspect.Post, distinct: [asc: p0.foo]}

    assert i(from(x in Post, distinct: [desc: x.foo])) ==
           ~s{from p0 in Inspect.Post, distinct: [desc: p0.foo]}
  end

  test "lock" do
    assert i(from(x in Post, lock: "FOOBAR")) ==
           ~s{from p0 in Inspect.Post, lock: "FOOBAR"}
  end

  test "preload" do
    assert i(from(x in Post, preload: :comments)) ==
           ~s"from p0 in Inspect.Post, preload: [:comments]"

    assert i(from(x in Post, join: y in assoc(x, :comments), preload: [comments: y])) ==
           ~s"from p0 in Inspect.Post, join: c1 in assoc(p0, :comments), preload: [comments: c1]"

    assert i(from(x in Post, join: y in assoc(x, :comments), preload: [comments: {y, post: x}])) ==
           ~s"from p0 in Inspect.Post, join: c1 in assoc(p0, :comments), preload: [comments: {c1, [post: p0]}]"
  end

  test "fragments" do
    value = "foobar"
    assert i(from(x in Post, where: fragment("downcase(?) == ?", x.id, ^value))) ==
           ~s{from p0 in Inspect.Post, where: fragment("downcase(?) == ?", p0.id, ^"foobar")}

    assert i(from(x in Post, where: fragment(^[title: [foo: "foobar"]]))) ==
           ~s{from p0 in Inspect.Post, where: fragment(title: [foo: "foobar"])}

    assert i(from(x in Post, where: fragment(title: [foo: ^value]))) ==
      ~s{from p0 in Inspect.Post, where: fragment(title: [foo: ^"foobar"])}
  end

  test "json_extract_path" do
    assert i(from(x in Post, select: json_extract_path(x.meta, ["author"]))) ==
             ~s{from p0 in Inspect.Post, select: p0.meta[\"author\"]}

    assert i(from(x in Post, select: x.meta["author"])) ==
             ~s{from p0 in Inspect.Post, select: p0.meta[\"author\"]}

    assert i(from(x in Post, select: x.meta["author"]["name"])) ==
             ~s{from p0 in Inspect.Post, select: p0.meta[\"author\"][\"name\"]}
  end

  test "inspect all" do
    string = """
    from p0 in Inspect.Post, join: c1 in assoc(p0, :comments), where: true, or_where: true,
    group_by: [p0.id], having: true, or_having: true, order_by: [asc: p0.id], limit: 1,
    offset: 1, lock: "FOO", distinct: [asc: 1], update: [set: [id: ^3]], select: 1,
    preload: [:likes], preload: [comments: c1]
    """
    |> String.trim
    |> String.replace("\n", " ")

    assert i(from(x in Post, join: y in assoc(x, :comments), where: true, or_where: true, group_by: x.id,
                             having: true, or_having: true, order_by: x.id, limit: 1, offset: 1,
                             lock: "FOO", select: 1, distinct: 1,
                             update: [set: [id: ^3]], preload: [:likes, comments: y])) == string
  end

  test "to_string all" do
    string = """
    from p0 in Inspect.Post,
      join: c1 in assoc(p0, :comments),
      where: true,
      or_where: true,
      group_by: [p0.id],
      having: true,
      or_having: true,
      union_all: (from p0 in Inspect.Post),
      order_by: [asc: p0.id],
      limit: 1,
      offset: 1,
      lock: "FOO",
      distinct: [asc: 1],
      update: [set: [id: 3]],
      select: 1,
      preload: [:likes],
      preload: [comments: c1]
    """
    |> String.trim

    assert Inspect.Ecto.Query.to_string(
      from(x in Post, join: y in assoc(x, :comments), where: true, or_where: true, group_by: x.id,
                      having: true, or_having: true, order_by: x.id, limit: 1, offset: 1, update: [set: [id: 3]],
                      lock: "FOO", distinct: 1, select: 1, preload: [:likes, comments: y],
                      union_all: ^from(y in Post))
    ) == string
  end

  # TODO: AST is represented as string differently on versions pre 1.13
  if Version.match?(System.version(), ">= 1.13.0-dev") do
    test "container values" do
      assert i(from(Post, select: <<1, 2, 3>>)) ==
             "from p0 in Inspect.Post, select: \"\\x01\\x02\\x03\""

      foo = <<1, 2, 3>>
      assert i(from(p in Post, select: {p, ^foo})) ==
             "from p0 in Inspect.Post, select: {p0, ^\"\\x01\\x02\\x03\"}"
    end
  else
    test "container values" do
      assert i(from(Post, select: <<1, 2, 3>>)) ==
             "from p0 in Inspect.Post, select: <<1, 2, 3>>"

      foo = <<1, 2, 3>>
      assert i(from(p in Post, select: {p, ^foo})) ==
             "from p0 in Inspect.Post, select: {p0, ^<<1, 2, 3>>}"
    end
  end

  test "select" do
    assert i(from(p in Post, select: p)) ==
           ~s{from p0 in Inspect.Post, select: p0}

    assert i(from(p in Post, select: [:foo])) ==
           ~s{from p0 in Inspect.Post, select: [:foo]}

    assert i(from(p in Post, select: struct(p, [:foo]))) ==
           ~s{from p0 in Inspect.Post, select: struct(p0, [:foo])}

    assert i(from(p in Post, select: merge(p, %{foo: p.foo}))) ==
           ~s"from p0 in Inspect.Post, select: merge(p0, %{foo: p0.foo})"
  end

  test "select after planner" do
    assert i(plan from(p in Post, select: p)) ==
           ~s{from p0 in Inspect.Post, select: p0}

    assert i(plan from(p in Post, select: [:foo])) ==
           ~s{from p0 in Inspect.Post, select: [:foo]}
  end

  test "params" do
    assert i(from(x in Post, where: ^123 > ^(1 * 3))) ==
           ~s{from p0 in Inspect.Post, where: ^123 > ^3}

    assert i(from(x in Post, where: x.id in ^[97])) ==
           ~s{from p0 in Inspect.Post, where: p0.id in ^[97]}
  end

  test "params after planner" do
    query = plan from(x in Post, where: ^123 > ^(1 * 3) and x.id in ^[1, 2, 3])
    assert i(query) ==
           ~s{from p0 in Inspect.Post, where: ^... > ^... and p0.id in ^...}
  end

  test "tagged types" do
    query = from(x in Post, select: type(^"1", :integer))
    assert i(query) == ~s{from p0 in Inspect.Post, select: type(^"1", :integer)}
    query = from(x in Post, select: type(^"1", x.visits))
    assert i(query) == ~s{from p0 in Inspect.Post, select: type(^"1", p0.visits)}
  end

  test "tagged types after planner" do
    query = from(x in Post, select: type(^"1", :integer)) |> plan
    assert i(query) == ~s{from p0 in Inspect.Post, select: type(^..., :integer)}
    query = from(x in Post, select: type(^"1", x.visits)) |> plan
    assert i(query) == ~s{from p0 in Inspect.Post, select: type(^..., :integer)}
  end

  defmodule MyParameterizedType do
    use Ecto.ParameterizedType

    def init(opts), do: Keyword.fetch!(opts, :param)
    def type(_), do: :custom
    def load(_, _, _), do: {:ok, :load}
    def dump( _, _, _),  do: {:ok, :dump}
    def cast( _, _),  do: {:ok, :cast}
    def equal?(true, _, _), do: true
    def equal?(_, _, _), do: false
    def embed_as(_, _), do: :self
  end
   
  test "parameterized types" do
    query = from(x in Post, select: type(^"foo", ^Ecto.ParameterizedType.init(MyParameterizedType, param: :foo)))
    assert i(query) == ~s<from p0 in Inspect.Post, select: type(^"foo", {:parameterized, Ecto.Query.InspectTest.MyParameterizedType, :foo})>
  end

  test "parameterized types after planner" do
    query = from(x in Post, select: type(^"foo", ^Ecto.ParameterizedType.init(MyParameterizedType, param: :foo))) |> plan()
    assert i(query) == ~s<from p0 in Inspect.Post, select: type(^..., {:parameterized, Ecto.Query.InspectTest.MyParameterizedType, :foo})>
  end

  def plan(query) do
    {query, _, _} = Ecto.Adapter.Queryable.plan_query(:all, Ecto.TestAdapter, query)
    query
  end

  def i(query) do
    assert "#Ecto.Query<" <> rest = inspect(query, safe: false)
    size = byte_size(rest)
    assert ">" = :binary.part(rest, size - 1, 1)
    :binary.part(rest, 0, size - 1)
  end
end
