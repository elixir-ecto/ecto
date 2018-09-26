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

    dynamic = dynamic([p], p.bar == ^1)
    assert inspect(dynamic([p], ^dynamic and p.foo == ^0)) ==
           "dynamic([p], p.bar == ^1 and p.foo == ^0)"

    dynamic = dynamic([o, b], b.user_id == ^1 or ^false)
    assert inspect(dynamic([o], o.type == ^2 and ^dynamic)) ==
           "dynamic([o, b], o.type == ^2 and (b.user_id == ^1 or ^false))"
  end

  test "invalid query" do
    assert i(select("posts", [a, b], {a.foo, b.bar})) ==
           "from p in \"posts\", select: {p.foo, unknown_binding_1!.bar}"
  end

  test "from" do
    assert i(from(Post, [])) ==
           ~s{from p in Inspect.Post}

    assert i(from(x in Post, [])) ==
          ~s{from p in Inspect.Post}

    assert i(from(x in "posts", [])) ==
           ~s{from p in "posts"}

    assert i(from(x in {"user_posts", Post}, [])) ==
           ~s[from p in {"user_posts", Inspect.Post}]

    assert i(from(subquery(Post), [])) ==
           ~s{from p in subquery(from p in Inspect.Post)}
  end

  test "join" do
    assert i(from(x in Post, join: y in Comment)) ==
           ~s{from p in Inspect.Post, join: c in Inspect.Comment, on: true}

    assert i(from(x in Post, join: y in Comment, on: x.id == y.id)) ==
           ~s{from p in Inspect.Post, join: c in Inspect.Comment, on: p.id == c.id}

    assert i(from(x in Post, full_join: y in Comment, on: x.id == y.id)) ==
           ~s{from p in Inspect.Post, full_join: c in Inspect.Comment, on: p.id == c.id}

    assert i(from(x in Post, full_join: y in {"user_comments", Comment}, on: x.id == y.id)) ==
           ~s[from p in Inspect.Post, full_join: c in {"user_comments", Inspect.Comment}, on: p.id == c.id]

    assert i(from(x in Post, left_join: y in assoc(x, :comments))) ==
           ~s{from p in Inspect.Post, left_join: c in assoc(p, :comments)}

    assert i(from(x in Post, left_join: y in assoc(x, :comments), on: y.published == true)) ==
           ~s{from p in Inspect.Post, left_join: c in assoc(p, :comments), on: c.published == true}

    assert i(from(x in Post, right_join: y in assoc(x, :post), join: z in assoc(y, :post))) ==
           ~s{from p0 in Inspect.Post, right_join: p1 in assoc(p0, :post), join: p2 in assoc(p1, :post)}

    assert i(from(x in Post, inner_join: y in fragment("foo ? and ?", x.id, ^1), on: y.id == x.id)) ==
           ~s{from p in Inspect.Post, join: f in fragment("foo ? and ?", p.id, ^1), on: f.id == p.id}

    assert i(from(x in Post, join: y in subquery(Comment), on: x.id == y.id)) ==
           ~s{from p in Inspect.Post, join: c in subquery(from c in Inspect.Comment), on: p.id == c.id}

    assert i(from(x in Post, join: y in ^from(c in Comment, where: true), on: x.id == y.id)) ==
           ~s{from p in Inspect.Post, join: c in ^#Ecto.Query<from c in Inspect.Comment, where: true>, on: p.id == c.id}
  end

  test "as" do
    assert i(from(x in Post, as: :post)) ==
      ~s{from p in Inspect.Post, as: :post}

    assert i(from(x in Post, join: y in Comment, as: :comment, on: x.id == y.id)) ==
      ~s{from p in Inspect.Post, join: c in Inspect.Comment, as: :comment, on: p.id == c.id}

    assert i(from(x in Post, inner_join: y in fragment("foo ? and ?", x.id, ^1), as: :foo, on: y.id == x.id)) ==
      ~s{from p in Inspect.Post, join: f in fragment("foo ? and ?", p.id, ^1), as: :foo, on: f.id == p.id}

    assert i(from(x in Post, join: y in subquery(Comment), as: :comment, on: x.id == y.id)) ==
      ~s{from p in Inspect.Post, join: c in subquery(from c in Inspect.Comment), as: :comment, on: p.id == c.id}
  end

  test "prefix" do
    assert i(from(x in Post, prefix: "post")) ==
      ~s{from p in Inspect.Post, prefix: "post"}

    assert i(from(x in Post, join: y in Comment, prefix: "comment", on: x.id == y.id)) ==
      ~s{from p in Inspect.Post, join: c in Inspect.Comment, prefix: "comment", on: p.id == c.id}

    assert i(from(x in Post, inner_join: y in fragment("foo ? and ?", x.id, ^1), prefix: "foo", on: y.id == x.id)) ==
      ~s{from p in Inspect.Post, join: f in fragment("foo ? and ?", p.id, ^1), prefix: "foo", on: f.id == p.id}

    assert i(from(x in Post, join: y in subquery(Comment), prefix: "comment", on: x.id == y.id)) ==
      ~s{from p in Inspect.Post, join: c in subquery(from c in Inspect.Comment), prefix: "comment", on: p.id == c.id}
  end

  test "where" do
    assert i(from(x in Post, where: x.foo == x.bar, where: true)) ==
           ~s{from p in Inspect.Post, where: p.foo == p.bar, where: true}
  end

  test "group by" do
    assert i(from(x in Post, group_by: [x.foo, x.bar], group_by: x.foobar)) ==
           ~s{from p in Inspect.Post, group_by: [p.foo, p.bar], group_by: [p.foobar]}
  end

  test "having" do
    assert i(from(x in Post, having: x.foo == x.bar, having: true)) ==
           ~s{from p in Inspect.Post, having: p.foo == p.bar, having: true}
  end

  test "window" do
    assert i(from(x in Post, windows: [a: [partition_by: x.foo]])) ==
           "from p in Inspect.Post, windows: [a: [partition_by: [p.foo]]]"

    assert i(from(x in Post, windows: [a: [partition_by: x.foo], b: [partition_by: x.bar]])) ==
           "from p in Inspect.Post, windows: [a: [partition_by: [p.foo]]], windows: [b: [partition_by: [p.bar]]]"

    assert i(from(x in Post, windows: [a: [partition_by: x.foo]], windows: [b: [partition_by: x.bar]])) ==
           "from p in Inspect.Post, windows: [a: [partition_by: [p.foo]]], windows: [b: [partition_by: [p.bar]]]"

    assert i(from(x in Post, windows: [a: [partition_by: [x.foo, x.bar]]])) ==
           "from p in Inspect.Post, windows: [a: [partition_by: [p.foo, p.bar]]]"
  end

  test "over" do
    assert i(from(x in Post, select: count(x.x) |> over(:x))) ==
           "from p in Inspect.Post, select: over(count(p.x), :x)"

    assert i(from(x in Post, select: count(x.x) |> over)) ==
           ~s{from p in Inspect.Post, select: over(count(p.x), [])}

    assert i(from(x in Post, select: count(x.x) |> over(partition_by: x.bar))) ==
           ~s{from p in Inspect.Post, select: over(count(p.x), partition_by: [p.bar])}
  end

  test "order by" do
    assert i(from(x in Post, order_by: [asc: x.foo, desc: x.bar], order_by: x.foobar)) ==
           ~s{from p in Inspect.Post, order_by: [asc: p.foo, desc: p.bar], order_by: [asc: p.foobar]}
  end

  test "union" do
    assert i(from(x in Post, union: from(y in Post), union_all: from(z in Post))) ==
             ~s{from p in Inspect.Post, union: from p in Inspect.Post, union_all: from p in Inspect.Post}
  end

  test "except" do
    assert i(from(x in Post, except: from(y in Post), except_all: from(y in Post))) ==
             ~s{from p in Inspect.Post, except: from p in Inspect.Post, except_all: from p in Inspect.Post}
  end

  test "intersect" do
    assert i(from(x in Post, intersect: from(y in Post), intersect_all: from(y in Post))) ==
             ~s{from p in Inspect.Post, intersect: from p in Inspect.Post, intersect_all: from p in Inspect.Post}
  end

  test "limit" do
    assert i(from(x in Post, limit: 123)) ==
           ~s{from p in Inspect.Post, limit: 123}
  end

  test "offset" do
    assert i(from(x in Post, offset: 123)) ==
           ~s{from p in Inspect.Post, offset: 123}
  end

  test "distinct" do
    assert i(from(x in Post, distinct: true)) ==
           ~s{from p in Inspect.Post, distinct: true}

    assert i(from(x in Post, distinct: [x.foo])) ==
           ~s{from p in Inspect.Post, distinct: [asc: p.foo]}

    assert i(from(x in Post, distinct: [desc: x.foo])) ==
           ~s{from p in Inspect.Post, distinct: [desc: p.foo]}
  end

  test "lock" do
    assert i(from(x in Post, lock: "FOOBAR")) ==
           ~s{from p in Inspect.Post, lock: "FOOBAR"}
  end

  test "preload" do
    assert i(from(x in Post, preload: :comments)) ==
           ~s"from p in Inspect.Post, preload: [:comments]"

    assert i(from(x in Post, join: y in assoc(x, :comments), preload: [comments: y])) ==
           ~s"from p in Inspect.Post, join: c in assoc(p, :comments), preload: [comments: c]"

    assert i(from(x in Post, join: y in assoc(x, :comments), preload: [comments: {y, post: x}])) ==
           ~s"from p in Inspect.Post, join: c in assoc(p, :comments), preload: [comments: {c, [post: p]}]"
  end

  test "fragments" do
    value = "foobar"
    assert i(from(x in Post, where: fragment("downcase(?) == ?", x.id, ^value))) ==
           ~s{from p in Inspect.Post, where: fragment("downcase(?) == ?", p.id, ^"foobar")}

    assert i(from(x in Post, where: fragment(^[title: [foo: "foobar"]]))) ==
           ~s{from p in Inspect.Post, where: fragment(title: [foo: "foobar"])}

    assert i(from(x in Post, where: fragment(title: [foo: ^value]))) ==
      ~s{from p in Inspect.Post, where: fragment(title: [foo: ^"foobar"])}
  end

  test "inspect all" do
    string = """
    from p in Inspect.Post, join: c in assoc(p, :comments), where: true, or_where: true,
    group_by: [p.id], having: true, or_having: true, order_by: [asc: p.id], limit: 1,
    offset: 1, lock: "FOO", distinct: [asc: 1], update: [set: [id: ^3]], select: 1,
    preload: [:likes], preload: [comments: c]
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
    from p in Inspect.Post,
      join: c in assoc(p, :comments),
      where: true,
      or_where: true,
      group_by: [p.id],
      having: true,
      or_having: true,
      union_all: from p in Inspect.Post,
      order_by: [asc: p.id],
      limit: 1,
      offset: 1,
      lock: "FOO",
      distinct: [asc: 1],
      update: [set: [id: 3]],
      select: 1,
      preload: [:likes],
      preload: [comments: c]
    """
    |> String.trim

    assert Inspect.Ecto.Query.to_string(
      from(x in Post, join: y in assoc(x, :comments), where: true, or_where: true, group_by: x.id,
                      having: true, or_having: true, order_by: x.id, limit: 1, offset: 1, update: [set: [id: 3]],
                      lock: "FOO", distinct: 1, select: 1, preload: [:likes, comments: y],
                      union_all: from(y in Post))
    ) == string
  end

  test "container values" do
    assert i(from(Post, select: <<1, 2, 3>>)) ==
           "from p in Inspect.Post, select: <<1, 2, 3>>"

    foo = <<1, 2, 3>>
    assert i(from(p in Post, select: {p, ^foo})) ==
           "from p in Inspect.Post, select: {p, ^<<1, 2, 3>>}"
  end

  test "select" do
    assert i(from(p in Post, select: p)) ==
           ~s{from p in Inspect.Post, select: p}

    assert i(from(p in Post, select: [:foo])) ==
           ~s{from p in Inspect.Post, select: [:foo]}

    assert i(from(p in Post, select: struct(p, [:foo]))) ==
           ~s{from p in Inspect.Post, select: struct(p, [:foo])}

    assert i(from(p in Post, select: merge(p, %{foo: p.foo}))) ==
           ~s"from p in Inspect.Post, select: merge(p, %{foo: p.foo})"
  end

  test "select after planner" do
    assert i(plan from(p in Post, select: p)) ==
           ~s{from p in Inspect.Post, select: p}

    assert i(plan from(p in Post, select: [:foo])) ==
           ~s{from p in Inspect.Post, select: [:foo]}
  end

  test "params" do
    assert i(from(x in Post, where: ^123 > ^(1 * 3))) ==
           ~s{from p in Inspect.Post, where: ^123 > ^3}

    assert i(from(x in Post, where: x.id in ^[97])) ==
           ~s{from p in Inspect.Post, where: p.id in ^[97]}
  end

  test "params after planner" do
    query = plan from(x in Post, where: ^123 > ^(1 * 3) and x.id in ^[1, 2, 3])
    assert i(query) ==
           ~s{from p in Inspect.Post, where: ^... > ^... and p.id in ^...}
  end

  test "tagged types" do
    query = from(x in Post, select: type(^"1", :integer))
    assert i(query) == ~s{from p in Inspect.Post, select: type(^"1", :integer)}
    query = from(x in Post, select: type(^"1", x.visits))
    assert i(query) == ~s{from p in Inspect.Post, select: type(^"1", p.visits)}
  end

  test "tagged types after planner" do
    query = from(x in Post, select: type(^"1", :integer)) |> plan
    assert i(query) == ~s{from p in Inspect.Post, select: type(^..., :integer)}
    query = from(x in Post, select: type(^"1", x.visits)) |> plan
    assert i(query) == ~s{from p in Inspect.Post, select: type(^..., :integer)}
  end

  def plan(query) do
    {query, _} = Ecto.Adapter.Queryable.plan_query(:all, Ecto.TestAdapter, query)
    query
  end

  def i(query) do
    assert "#Ecto.Query<" <> rest = inspect query
    size = byte_size(rest)
    assert ">" = :binary.part(rest, size - 1, 1)
    :binary.part(rest, 0, size - 1)
  end
end
