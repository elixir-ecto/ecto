Code.require_file "../../test_helper.exs", __DIR__

defmodule Ecto.Query.ValidatorTest do
  use ExUnit.Case, async: true

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

    dataset :post_entity do
      field :text, :string
    end
  end


  test "valid query with bindings" do
    query = from(p in PostEntity) |> from(c in CommentEntity) |> select([p, c], { p.title, c.text })
    QueryUtil.validate(query)
  end

  test "invalid query" do
    query = select(Query[], [], 123)
    assert_raise Ecto.InvalidQuery, %r"a query must have a from expression", fn ->
      QueryUtil.validate(query)
    end

    query = from(p in PostEntity) |> from(c in CommentEntity)
    message = %r"a query must have a select expression if querying from more than one entity"
    assert_raise Ecto.InvalidQuery, message, fn ->
      QueryUtil.validate(query)
    end
  end

  test "where expression must be boolean" do
    query = from(p in PostEntity) |> where([p], p.title) |> select([], 123)
    assert_raise Ecto.InvalidQuery, %r"where expression has to be of boolean type", fn ->
      QueryUtil.validate(query)
    end
  end

  test "entity field types" do
    query = from(p in PostEntity) |> select([p], p.title + 2)
    assert_raise Ecto.InvalidQuery, %r"both arguments of `\+` must be of a number type", fn ->
      QueryUtil.validate(query)
    end
  end

  test "unknown field" do
    query = from(p in PostEntity) |> select([p], p.unknown)
    assert_raise Ecto.InvalidQuery, %r"unknown field `p.unknown`", fn ->
      QueryUtil.validate(query)
    end
  end

  test "valid expressions" do
    query = from(p in PostEntity) |> select([p], p.id + 2)
    QueryUtil.validate(query)

    query = from(p in PostEntity) |> select([p], p.id == 2)
    QueryUtil.validate(query)

    query = from(p in PostEntity) |> select([p], p.title == "abc")
    QueryUtil.validate(query)

    query = from(p in PostEntity) |> select([], 1 + +123)
    QueryUtil.validate(query)

    query = from(p in PostEntity) |> where([p], p.id < 10) |> select([], 0)
    QueryUtil.validate(query)

    query = from(p in PostEntity) |> where([], true or false) |> select([], 0)
    QueryUtil.validate(query)
  end

  test "invalid expressions" do
    query = from(p in PostEntity) |> select([], :atom)
    assert_raise Ecto.InvalidQuery, %r"atoms are not allowed", fn ->
      QueryUtil.validate(query)
    end

    query = from(p in PostEntity) |> select([p], p.id + "abc")
    assert_raise Ecto.InvalidQuery, %r"both arguments of `\+` must be of a number type", fn ->
      QueryUtil.validate(query)
    end

    query = from(p in PostEntity) |> select([p], p.id == "abc")
    assert_raise Ecto.InvalidQuery, %r"both arguments of `==` types must match", fn ->
      QueryUtil.validate(query)
    end

    query = from(p in PostEntity) |> select([], -"abc")
    assert_raise Ecto.InvalidQuery, %r"argument of `-` must be of a number type", fn ->
      QueryUtil.validate(query)
    end

    query = from(p in PostEntity) |> select([], 1 < "123")
    assert_raise Ecto.InvalidQuery, %r"both arguments of `<` must be of a number type", fn ->
      QueryUtil.validate(query)
    end

    query = from(p in PostEntity) |> where([], true or 123) |> select([], 0)
    assert_raise Ecto.InvalidQuery, %r"both arguments of `or` must be of type boolean", fn ->
      QueryUtil.validate(query)
    end
  end
end
