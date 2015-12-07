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

  test "from" do
    assert i(from(Post, [])) ==
           ~s{from p in Inspect.Post}

    assert i(from(x in Post, [])) ==
          ~s{from p in Inspect.Post}

    assert i(from(x in "posts", [])) ==
           ~s{from p in "posts"}

    assert i(from(x in {"user_posts", Post}, [])) ==
           ~s[from p in {"user_posts", Inspect.Post}]
  end

  test "join" do
    assert i(from(x in Post, join: y in Comment, on: x.id == y.id)) ==
           ~s{from p in Inspect.Post, join: c in Inspect.Comment, on: p.id == c.id}

    assert i(from(x in Post, full_join: y in Comment, on: x.id == y.id)) ==
           ~s{from p in Inspect.Post, full_join: c in Inspect.Comment, on: p.id == c.id}

    assert i(from(x in Post, full_join: y in {"user_comments", Comment}, on: x.id == y.id)) ==
           ~s[from p in Inspect.Post, full_join: c in {"user_comments", Inspect.Comment}, on: p.id == c.id]

    assert i(from(x in Post, left_join: y in assoc(x, :comments))) ==
           ~s{from p in Inspect.Post, left_join: c in assoc(p, :comments)}

    assert i(from(x in Post, right_join: y in assoc(x, :post), join: z in assoc(y, :post))) ==
           ~s{from p0 in Inspect.Post, right_join: p1 in assoc(p0, :post), join: p2 in assoc(p1, :post)}

    assert i(from(x in Post, inner_join: y in fragment("foo ? and ?", x.id, ^1), on: y.id == x.id)) ==
           ~s{from p in Inspect.Post, join: f in fragment("foo ? and ?", p.id, ^1), on: f.id == p.id}
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

  test "order by" do
    assert i(from(x in Post, order_by: [asc: x.foo, desc: x.bar], order_by: x.foobar)) ==
           ~s{from p in Inspect.Post, order_by: [asc: p.foo, desc: p.bar], order_by: [asc: p.foobar]}
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
           ~s{from p in Inspect.Post, distinct: [p.foo]}
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
    from p in Inspect.Post, join: c in assoc(p, :comments), where: true,
    group_by: [p.id], having: true, order_by: [asc: p.id], limit: 1,
    offset: 1, lock: "FOO", distinct: [1], update: [set: [id: ^3]], select: 1,
    preload: [:likes], preload: [comments: c]
    """
    |> String.rstrip
    |> String.replace("\n", " ")

    assert i(from(x in Post, join: y in assoc(x, :comments), where: true, group_by: x.id,
                             having: true, order_by: x.id, limit: 1, offset: 1,
                             lock: "FOO", select: 1, distinct: 1,
                             update: [set: [id: ^3]], preload: [:likes, comments: y])) == string
  end

  test "to_string all" do
    string = """
    from p in Inspect.Post,
      join: c in assoc(p, :comments),
      where: true,
      group_by: [p.id],
      having: true,
      order_by: [asc: p.id],
      limit: 1,
      offset: 1,
      lock: "FOO",
      distinct: [1],
      update: [set: [id: 3]],
      select: 1,
      preload: [:likes],
      preload: [comments: c]
    """
    |> String.rstrip

    assert Inspect.Ecto.Query.to_string(
      from(x in Post, join: y in assoc(x, :comments), where: true, group_by: x.id,
                      having: true, order_by: x.id, limit: 1, offset: 1, update: [set: [id: 3]],
                      lock: "FOO", distinct: 1, select: 1, preload: [:likes, comments: y])
    ) == string
  end

  test "container values" do
    assert i(from(Post, select: <<1, 2, 3>>)) ==
           "from p in Inspect.Post, select: <<1, 2, 3>>"

    foo = <<1, 2, 3>>
    assert i(from(Post, select: ^foo)) ==
           "from p in Inspect.Post, select: ^<<1, 2, 3>>"
  end

  test "params" do
    assert i(from(x in Post, where: ^123 > ^(1 * 3))) ==
           ~s{from p in Inspect.Post, where: ^123 > ^3}
  end

  test "params after planner" do
    query = plan from(x in Post, where: ^123 > ^(1 * 3) and x.id in ^[1, 2, 3])
    assert i(query) ==
           ~s{from p in Inspect.Post, where: ^... > ^... and p.id in ^..., select: p}
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
    {query, _params, _key} = Ecto.Query.Planner.prepare(query, :all, Ecto.TestAdapter)
    Ecto.Query.Planner.normalize(query, :all, Ecto.TestAdapter)
  end

  def i(query) do
    assert "#Ecto.Query<" <> rest = inspect query
    size = byte_size(rest)
    assert ">" = :binary.part(rest, size-1, 1)
    :binary.part(rest, 0, size-1)
  end
end
