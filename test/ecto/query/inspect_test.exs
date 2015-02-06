defmodule Inspect.Post do
  use Ecto.Model

  schema "posts" do
    has_many :comments, Inspect.Comment
    has_one :post, Inspect.Post
  end
end

defmodule Inspect.Comment do
  use Ecto.Model

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
  end

  test "join" do
    assert i(from(x in Post, join: y in Comment, on: x.id == y.id)) ==
           ~s{from p in Inspect.Post, join: c in Inspect.Comment, on: p.id == c.id}

    assert i(from(x in Post, join: y in assoc(x, :comments))) ==
           ~s{from p in Inspect.Post, join: c in assoc(p, :comments)}

    assert i(from(x in Post, join: y in assoc(x, :post), join: z in assoc(y, :post))) ==
           ~s{from p0 in Inspect.Post, join: p1 in assoc(p0, :post), join: p2 in assoc(p1, :post)}

    assert i(from(x in Post, left_join: y in assoc(x, :comments))) ==
           ~s{from p in Inspect.Post, left_join: c in assoc(p, :comments)}
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

  test "lock" do
    assert i(from(x in Post, lock: true)) ==
           ~s{from p in Inspect.Post, lock: true}

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
  end

  test "inspect all" do
    string = """
    from p in Inspect.Post, join: c in assoc(p, :comments), where: true,
    group_by: [p.id], having: true, order_by: [asc: p.id], limit: 1,
    offset: 1, lock: true, distinct: [1], select: 1, preload: [:likes], preload: [comments: c]
    """
    |> String.rstrip
    |> String.replace("\n", " ")

    assert i(from(x in Post, join: y in assoc(x, :comments), where: true, group_by: x.id,
                             having: true, order_by: x.id, limit: 1, offset: 1,
                             lock: true, select: 1, distinct: 1, preload: [:likes, comments: y])) == string
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
      lock: true,
      distinct: [1],
      select: 1,
      preload: [:likes],
      preload: [comments: c]
    """
    |> String.rstrip

    assert Inspect.Ecto.Query.to_string(
      from(x in Post, join: y in assoc(x, :comments), where: true, group_by: x.id,
                      having: true, order_by: x.id, limit: 1, offset: 1,
                      lock: true, distinct: 1, select: 1, preload: [:likes, comments: y])
    ) == string
  end

  test "container values" do
    assert i(from(Post, select: {<<1, 2, 3>>, uuid(<<0>>), [0]})) ==
           "from p in Inspect.Post, select: {<<1, 2, 3>>, uuid(<<0>>), [0]}"

    foo = <<1, 2, 3>>
    assert i(from(Post, select: type(^foo, :uuid))) ==
           "from p in Inspect.Post, select: type(^<<1, 2, 3>>, :uuid)"
  end

  test "params" do
    assert i(from(x in Post, where: ^123 > ^(1 * 3))) ==
           ~s{from p in Inspect.Post, where: ^123 > ^3}
  end

  test "params after planner" do
    query = from(x in Post, where: ^123 > ^(1 * 3))
            |> Ecto.Query.Planner.prepare(%{})
            |> elem(0)
            |> Ecto.Query.Planner.normalize(%{}, [])
    assert i(query) == ~s{from p in Inspect.Post, where: ^... > ^..., select: p}
  end

  def i(query) do
    assert "#Ecto.Query<" <> rest = inspect query
    size = byte_size(rest)
    assert ">" = :binary.part(rest, size-1, 1)
    :binary.part(rest, 0, size-1)
  end
end
