defmodule Ecto.Query.ValidatorTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  alias Ecto.Query
  alias Ecto.Query.Planner
  alias Ecto.Query.Validator

  defmodule Post do
    use Ecto.Model

    schema :posts do
      field :title, :string
      field :text, :string
      field :temp, :string, virtual: true
      has_many :comments, Ecto.Query.ValidatorTest.Comment
      has_one :permalink, Ecto.Query.ValidatorTest.Permalink
    end
  end

  def validate(query) do
    query
    |> Planner.plan(%{})
    |> Validator.validate()
  end

  test "unknown field" do
    query = Post |> select([p], p.unknown)
    assert_raise Ecto.QueryError, ~r"unknown field `unknown` on `Ecto.Query.ValidatorTest.Post`", fn ->
      validate(query)
    end
  end

  test "invalid expressions" do
    query = Post |> select([p], p.id == "abc")
    assert_raise Ecto.Query.TypeCheckError, fn ->
      validate(query)
    end

    query = Post |> select([p], 1 < p.title)
    assert_raise Ecto.Query.TypeCheckError, fn ->
      validate(query)
    end

    query = Post |> where([p], true or p.title) |> select([], 0)
    assert_raise Ecto.Query.TypeCheckError, fn ->
      validate(query)
    end
  end

  test "valid in expression" do
    query = Post |> select([], 1 in [1,2,3])
    validate(query)
  end

  test "invalid in expression" do
    query = Post |> select([p], 1 in p.title)
    assert_raise Ecto.Query.TypeCheckError, fn ->
      validate(query)
    end
  end

  test "cannot reference virtual field" do
    query = Post |> select([c], c.temp)
    assert_raise Ecto.QueryError, fn ->
      validate(query)
    end
  end

  test "cannot preload without model" do
    query = "posts" |> preload(:comments)
    assert_raise Ecto.QueryError, fn ->
      validate(query)
    end
  end

  test "model have to be selected with preload" do
    query = Post |> preload(:comments) |> select([p], p)
    validate(query)

    query = Post |> preload(:comments) |> select([p], 0)
    assert_raise Ecto.QueryError, fn ->
      validate(query)
    end
  end

  test "source only query" do
    query = from(p in "posts", select: p.any_post)
    validate(query)
  end
end
