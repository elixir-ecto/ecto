Code.require_file "../../test_helper.exs", __DIR__

defmodule Ecto.Query.ValidatorTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  defmodule PostEntity do
    use Ecto.Entity
    table_name :post_entity

    primary_key
    field :title, :string
  end

  defmodule CommentEntity do
    use Ecto.Entity
    table_name :post_entity

    primary_key
    field :text, :string
  end


  test "valid query with bindings" do
    query = from(p in PostEntity) |> from(c in CommentEntity) |> select([p, c], { p, c })
    validate(query)
  end

  test "invalid query" do
    query = select([], 123)
    assert_raise Ecto.InvalidQuery, "a query must have a from expression", fn ->
      validate(query)
    end
    query = from(p in PostEntity)
    assert_raise Ecto.InvalidQuery, "a query must have a select expression", fn ->
      validate(query)
    end
  end

  test "invalid from query" do
    query = from(p in PostEntity) |> from(p in CommentEntity) |> select([], 123)
    assert_raise Ecto.InvalidQuery, "variable `p` is already bound in a query expression", fn ->
      validate(query)
    end

    query = from(p in NotAnEntity) |> select([], 123)
    assert_raise Ecto.InvalidQuery, "`NotAnEntity` is not an Ecto entity", fn ->
      validate(query)
    end
  end

  test "where expression must be boolean" do
    query = from(p in PostEntity) |> where([p], p.title) |> select([], 123)
    assert_raise Ecto.InvalidQuery, "where expression has to be of boolean type", fn ->
      validate(query)
    end
  end

  test "entity field types" do
    query = from(p in PostEntity) |> select([p], p.title + 2)
    assert_raise Ecto.InvalidQuery, "both arguments of `+` must be of a number type", fn ->
      validate(query)
    end
  end

  test "unbound var" do
    query = from(p in PostEntity) |> select([q], q.title)
    assert_raise Ecto.InvalidQuery, "`q` not bound in a from expression", fn ->
      validate(query)
    end
  end

  test "unknown field" do
    query = from(p in PostEntity) |> select([p], p.unknown)
    assert_raise Ecto.InvalidQuery, "unknown field `p.unknown`", fn ->
      validate(query)
    end
  end

  test "valid expressions" do
    query = from(p in PostEntity) |> select([p], p.id + 2)
    validate(query)

    query = from(p in PostEntity) |> select([p], p.id == 2)
    validate(query)

    query = from(p in PostEntity) |> select([p], p.title == "abc")
    validate(query)

    query = from(p in PostEntity) |> select([], 1 + +123)
    validate(query)

    query = from(p in PostEntity) |> where([p], p.id < 10) |> select([], 0)
    validate(query)

    query = from(p in PostEntity) |> where([], true or false) |> select([], 0)
    validate(query)
  end

  test "invalid expressions" do
    query = from(p in PostEntity) |> select([p], p.id + "abc")
    assert_raise Ecto.InvalidQuery, "both arguments of `+` must be of a number type", fn ->
      validate(query)
    end

    query = from(p in PostEntity) |> select([p], p.id == "abc")
    assert_raise Ecto.InvalidQuery, "both arguments of `==` types must match", fn ->
      validate(query)
    end

    query = from(p in PostEntity) |> select([], -"abc")
    assert_raise Ecto.InvalidQuery, "argument of `-` must be of a number type", fn ->
      validate(query)
    end

    query = from(p in PostEntity) |> select([], 1 < "123")
    assert_raise Ecto.InvalidQuery, "both arguments of `<` must be of a number type", fn ->
      validate(query)
    end

    query = from(p in PostEntity) |> where([], true or 123) |> select([], 0)
    assert_raise Ecto.InvalidQuery, "both arguments of `or` must be of type boolean", fn ->
      validate(query)
    end
  end
end
