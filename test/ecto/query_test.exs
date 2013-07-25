Code.require_file "../test_helper.exs", __DIR__

defmodule Ecto.QueryTest do
  use ExUnit.Case, async: true

  import Ecto.TestHelpers
  import Ecto.Query
  alias Ecto.Query.Query
  alias Ecto.Query.QueryUtil

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

  test "call queryable on every merge" do
    query = from(PostEntity) |> select([p], p.title)
    query |> QueryUtil.normalize |> QueryUtil.validate

    query = from(PostEntity) |> where([p], p.title == "42")
    query |> QueryUtil.normalize |> QueryUtil.validate

    query = from(PostEntity) |> order_by([p], p.title)
    query |> QueryUtil.normalize |> QueryUtil.validate

    query = from(PostEntity) |> limit(42)
    query |> QueryUtil.normalize |> QueryUtil.validate

    query = from(PostEntity) |> offset(43)
    query |> QueryUtil.normalize |> QueryUtil.validate

    query = select(PostEntity, [p], p.title)
    query |> QueryUtil.normalize |> QueryUtil.validate

    query = where(PostEntity, [p], p.title == "42")
    query |> QueryUtil.normalize |> QueryUtil.validate

    query = order_by(PostEntity, [p], p.title)
    query |> QueryUtil.normalize |> QueryUtil.validate

    query = limit(PostEntity, 42)
    query |> QueryUtil.normalize |> QueryUtil.validate

    query = offset(PostEntity, 43)
    query |> QueryUtil.normalize |> QueryUtil.validate
  end

  test "vars are order dependent" do
    query = from(p in PostEntity) |> select([q], q.title)
    QueryUtil.validate(query)
  end

  test "can append to selected query" do
    query = from(p in PostEntity) |> select([], 1) |> from(q in PostEntity)
    QueryUtil.validate(query)
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

    assert from(p in PostEntity, where: true, from: q in PostEntity, select: 1) == from(p in PostEntity) |> where([p], true) |> from(q in PostEntity) |> select([p, q], 1)
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

  test "cannot bind too many vars" do
    assert_raise Ecto.InvalidQuery, "cannot bind more variables than there are from expressions", fn ->
      from(p in PostEntity) |> select([p, q], p.title)
    end

    assert_raise Ecto.InvalidQuery, "cannot bind more variables than there are from expressions", fn ->
      query = from(p in PostEntity)
      from([p, q] in query, select: p.title)
    end
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
end
