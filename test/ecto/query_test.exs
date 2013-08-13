defmodule Ecto.QueryTest do
  use ExUnit.Case, async: true

  import Ecto.TestHelpers
  import Ecto.Query
  alias Ecto.Query.Query
  alias Ecto.Query.Util

  defmodule PostEntity do
    use Ecto.Entity

    dataset :post_entity do
      field :title, :string
    end
  end

  defmodule CommentEntity do
    use Ecto.Entity

    dataset :comments do
      field :text, :string
    end
  end

  def validate(query), do: query |> Util.normalize |> Util.validate([Ecto.Query.API])


  test "call queryable on every merge" do
    query = from(PostEntity) |> select([p], p.title)
    validate(query)

    query = from(PostEntity) |> where([p], p.title == "42")
    validate(query)

    query = from(PostEntity) |> order_by([p], p.title)
    validate(query)

    query = from(PostEntity) |> limit(42)
    validate(query)

    query = from(PostEntity) |> offset(43)
    validate(query)

    query = select(PostEntity, [p], p.title)
    validate(query)

    query = where(PostEntity, [p], p.title == "42")
    validate(query)

    query = order_by(PostEntity, [p], p.title)
    validate(query)

    query = limit(PostEntity, 42)
    validate(query)

    query = offset(PostEntity, 43)
    validate(query)
  end

  test "vars are order dependent" do
    query = from(p in PostEntity) |> select([q], q.title)
    validate(query)
  end

  test "can append to selected query" do
    query = from(p in PostEntity) |> select([], 1) |> where([], true)
    validate(query)
  end

  test "only one select is allowed" do
    assert_raise Ecto.InvalidQuery, "only one select expression is allowed in query", fn ->
      from(p in PostEntity) |> select([], 1) |> select([], 2)
    end
  end

  test "only one limit or offset is allowed" do
    assert_raise Ecto.InvalidQuery, "only one limit expression is allowed in query", fn ->
      from(p in PostEntity) |> limit([], 1) |> limit([], 2) |> select([], 3)
    end

    assert_raise Ecto.InvalidQuery, "only one offset expression is allowed in query", fn ->
      from(p in PostEntity) |> offset([], 1) |> offset([], 2) |> select([], 3)
    end
  end

  test "binding should be list of variables" do
    assert_raise Ecto.InvalidQuery, "binding should be list of variables", fn ->
      delay_compile select(Query[], [0], 1)
    end
  end

  test "keyword query" do
    # queries need to be on the same line or == wont work

    assert from(p in PostEntity, []) == from(p in PostEntity)

    assert from(p in PostEntity, select: 1+2) == from(p in PostEntity) |> select([p], 1+2)

    assert from(p in PostEntity, where: 1<2) == from(p in PostEntity) |> where([p], 1<2)
  end

  test "variable is already defined" do
    assert_raise Ecto.InvalidQuery, "variable `p` is already defined in query", fn ->
      delay_compile(from(p in PostEntity, from: p in PostEntity))
    end
  end

  test "extend keyword query" do
    query = from(p in PostEntity)
    assert (query |> select([p], p.title)) == from(p in query, select: p.title)

    query = from(p in PostEntity)
    assert (query |> select([p], p.title)) == from([p] in query, select: p.title)

    query = PostEntity
    assert (query |> select([p], p.title)) == from([p] in query, select: p.title)
  end

  test "cannot bind non-Queryable in from" do
    assert_raise Protocol.UndefinedError, fn ->
      from(p in 123) |> select([p], p.title)
    end

    assert_raise Protocol.UndefinedError, fn ->
      from(p in NotAnEntity) |> select([p], p.title)
    end
  end

  test "validate from expression" do
    delay_compile(from(PostEntity, []))

    assert_raise Ecto.InvalidQuery, fn ->
      delay_compile(from(PostEntity, [123]))
    end

    assert_raise Ecto.InvalidQuery, fn ->
      delay_compile(from(PostEntity, 123))
    end
  end

  test "unbound _ var" do
    assert_raise Ecto.InvalidQuery, fn ->
      delay_compile(from(PostEntity) |> select([], _.x))
    end

    query = from(PostEntity) |> select([_], 0)
    validate(query)

    query = from(PostEntity) |> join([], CommentEntity, true) |> select([_, c], c.text)
    validate(query)

    query = from(PostEntity) |> join([], CommentEntity, true) |> select([p, _], p.title)
    validate(query)

    query = from(PostEntity) |> join([], CommentEntity, true) |> select([_, _], 0)
    validate(query)
  end

  test "binding collision" do
    assert_raise Ecto.InvalidQuery, "variable `x` is already defined in query", fn ->
      delay_compile(from(PostEntity) |> from(CommentEntity) |> select([x, x], x.id))
    end

    assert_raise Ecto.InvalidQuery, "variable `x` is already defined in query", fn ->
      delay_compile(from(x in PostEntity, from: x in CommentEntity, select: x.id))
    end
  end

  test "join on keyword query" do
    from(c in CommentEntity, join: p in PostEntity, on: c.text == "", select: c)

    assert_raise Ecto.InvalidQuery, "an `on` query expression must follow a `from`", fn ->
      delay_compile(from(c in CommentEntity, on: c.text == "", select: c))
    end
    assert_raise Ecto.InvalidQuery, "a `join` query expression have to be followed by `on`", fn ->
      delay_compile(from(c in CommentEntity, join: p in PostEntity, select: c))
    end
  end

  test "join queries adds binds" do
    from(c in CommentEntity, join: p in PostEntity, on: true, select: { p.title, c.text })
    from(CommentEntity) |> join([c], p in PostEntity, true) |> select([c,p], { p.title, c.text })
  end
end
