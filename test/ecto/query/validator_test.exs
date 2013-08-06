defmodule Ecto.Query.ValidatorTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  alias Ecto.Query.Query
  alias Ecto.Queryable
  alias Ecto.Query.QueryUtil

  defmodule PostEntity do
    use Ecto.Entity

    dataset :post_entity do
      field :title, :string
    end
  end

  defmodule CommentEntity do
    use Ecto.Entity

    dataset :post_entity do
      field :text, :string
    end
  end


  test "valid query with bindings" do
    query = from(PostEntity) |> from(CommentEntity) |> select([p, c], { p.title, c.text })
    QueryUtil.validate(query)
  end

  test "invalid query" do
    query = select(Query[], [], 123)
    assert_raise Ecto.InvalidQuery, %r"a query must have a from expression", fn ->
      QueryUtil.validate(query)
    end

    query = from(PostEntity) |> from(c in CommentEntity)
    message = %r"a query must have a select expression if querying from more than one entity"
    assert_raise Ecto.InvalidQuery, message, fn ->
      QueryUtil.validate(query)
    end
  end

  test "where expression must be boolean" do
    query = from(PostEntity) |> where([p], p.title) |> select([], 123)
    assert_raise Ecto.InvalidQuery, %r"where expression", fn ->
      QueryUtil.validate(query)
    end
  end

  test "having expression must be boolean" do
    query = from(PostEntity) |> having([], "abc") |> select([], 123)
    assert_raise Ecto.InvalidQuery, %r"having expression", fn ->
      QueryUtil.validate(query)
    end
  end

  test "entity field types" do
    query = from(PostEntity) |> select([p], p.title + 2)
    assert_raise Ecto.TypeCheckError, fn ->
      QueryUtil.validate(query)
    end
  end

  test "unknown field" do
    query = from(PostEntity) |> select([p], p.unknown)
    assert_raise Ecto.InvalidQuery, %r"unknown field `p.unknown`", fn ->
      QueryUtil.validate(query)
    end
  end

  test "valid expressions" do
    query = from(PostEntity) |> select([p], p.id + 2)
    QueryUtil.validate(query)

    query = from(PostEntity) |> select([p], p.id == 2)
    QueryUtil.validate(query)

    query = from(PostEntity) |> select([p], p.title == "abc")
    QueryUtil.validate(query)

    query = from(PostEntity) |> select([], 1 + +123)
    QueryUtil.validate(query)

    query = from(PostEntity) |> where([p], p.id < 10) |> select([], 0)
    QueryUtil.validate(query)

    query = from(PostEntity) |> where([], true or false) |> select([], 0)
    QueryUtil.validate(query)
  end

  test "invalid expressions" do
    query = from(PostEntity) |> select([p], p.id + "abc")
    assert_raise Ecto.TypeCheckError, fn ->
      QueryUtil.validate(query)
    end

    query = from(PostEntity) |> select([p], p.id == "abc")
    assert_raise Ecto.TypeCheckError, fn ->
      QueryUtil.validate(query)
    end

    query = from(PostEntity) |> select([p], -p.title)
    assert_raise Ecto.TypeCheckError, fn ->
      QueryUtil.validate(query)
    end

    query = from(PostEntity) |> select([p], 1 < p.title)
    assert_raise Ecto.TypeCheckError, fn ->
      QueryUtil.validate(query)
    end

    query = from(PostEntity) |> where([p], true or p.title) |> select([], 0)
    assert_raise Ecto.TypeCheckError, fn ->
      QueryUtil.validate(query)
    end
  end

  test "valid in expression" do
    query = from(PostEntity) |> select([], 1 in [1,2,3])
    QueryUtil.validate(query)

    query = from(PostEntity) |> select([], '1' in ['1','2','3'])
    QueryUtil.validate(query)

    query = from(PostEntity) |> select([], (2+2) in 1..5)
    QueryUtil.validate(query)

    query = from(PostEntity) |> select([], [1] in [[1], [1, 2, 3], []])
    QueryUtil.validate(query)
  end

  test "invalid in expression" do
    query = from(PostEntity) |> select([p], 1 in p.title)
    assert_raise Ecto.TypeCheckError, fn ->
      QueryUtil.validate(query)
    end
  end

  test "valid .. expression" do
    query = from(PostEntity) |> select([], 1 .. 3)
    QueryUtil.validate(query)
  end

  test "invalid .. expression" do
    query = from(PostEntity) |> select([], 1 .. '3')
    assert_raise Ecto.TypeCheckError, fn ->
      QueryUtil.validate(query)
    end

    query = from(PostEntity) |> select([], "1" .. 3)
    assert_raise Ecto.TypeCheckError, fn ->
      QueryUtil.validate(query)
    end
  end

  test "list expression" do
    query = from(PostEntity) |> where([p], [p.title, p.title] == nil) |> select([], 0)
    QueryUtil.validate(query)

    query = from(PostEntity) |> where([p], [p.title, p.title] == 1) |> select([], 0)
    assert_raise Ecto.TypeCheckError, fn ->
      QueryUtil.validate(query)
    end
  end

  test "having without group_by" do
    query = from(PostEntity) |> having([], true) |> select([], 0)
    QueryUtil.validate(query)

    query = from(PostEntity) |> having([p], p.id) |> select([], 0)
    assert_raise Ecto.InvalidQuery, %r"`p.id` must appear in `group_by`", fn ->
      QueryUtil.validate(query)
    end
  end

  test "having with group_by" do
    query = from(PostEntity) |> group_by([p], p.id) |> having([p], p.id == 0) |> select([p], p.id)
    QueryUtil.validate(query)

    query = from(PostEntity) |> group_by([p], p.id) |> having([p], p.title) |> select([], 0)
    assert_raise Ecto.InvalidQuery, %r"`p.title` must appear in `group_by`", fn ->
      QueryUtil.validate(query)
    end
  end

  test "group_by groups expression" do
    query = from(PostEntity) |> group_by([p], p.id) |> select([p], p.id)
    QueryUtil.validate(query)

    query = from(PostEntity) |> group_by([p], p.id) |> select([p], p.title)
    assert_raise Ecto.InvalidQuery, %r"`p.title` must appear in `group_by`", fn ->
      QueryUtil.validate(query)
    end
  end

  test "group_by doesn't group where" do
    query = from(PostEntity) |> group_by([p], p.id) |> where([p], p.title == "") |> select([p], p.id)
    QueryUtil.validate(query)
  end

  test "allow functions" do
    query = from(PostEntity) |> select([], avg(0))
    QueryUtil.validate(query)
  end

  test "allow grouped fields in aggregate" do
    query = from(PostEntity) |> group_by([p], p.id) |> select([p], avg(p.id))
    QueryUtil.validate(query)
  end

  test "allow non-grouped fields in aggregate" do
    query = from(PostEntity) |> group_by([p], p.title) |> select([p], count(p.id))
    QueryUtil.validate(query)
  end

  test "don't allow nested aggregates" do
    query = from(PostEntity) |> select([p], count(count(p.id)))
    assert_raise Ecto.InvalidQuery, "aggregate function calls cannot be nested", fn ->
      QueryUtil.validate(query)
    end
  end

  test "nils only allowed in == and !=" do
    query = from(PostEntity) |> select([p], 1 == nil)
    QueryUtil.validate(query)

    query = from(PostEntity) |> select([p], nil != "abc")
    QueryUtil.validate(query)

    query = from(PostEntity) |> select([p], 1 + nil)
    assert_raise Ecto.TypeCheckError, fn ->
      QueryUtil.validate(query)
    end
  end
end
