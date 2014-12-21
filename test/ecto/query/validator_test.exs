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
      has_many :comments, Ecto.Query.ValidatorTest.Comment
      has_one :permalink, Ecto.Query.ValidatorTest.Permalink
    end
  end

  defmodule Permalink do
    use Ecto.Model

    schema :comments, primary_key: false do
      belongs_to :post, Ecto.Query.ValidatorTest.Post
    end
  end

  defmodule Comment do
    use Ecto.Model

    schema :comments do
      field :text, :string
      field :temp, :string, virtual: true
      field :posted, :datetime
      field :day, :date
      field :time, :time
      belongs_to :post, Ecto.Query.ValidatorTest.Post
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
    query = Comment |> select([c], c.temp)
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

  test "assoc selector" do
    query = from(p in Post, join: c in p.comments, select: assoc(p, comments: c))
    validate(query)

    query = from(p in Post, join: c in p.comments, select: assoc(c, post: p))
    validate(query)

    query = from(p in Post, join: c in p.comments, select: assoc(p, not_field: c))
    assert_raise Ecto.QueryError, ~r"field `Ecto.Query.ValidatorTest.Post.not_field` is not an association", fn ->
      validate(query)
    end

    query = from(p in Post, join: c in p.comments, select: assoc(p, permalink: c))
    assert_raise Ecto.QueryError, ~r"doesn't match given model", fn ->
      validate(query)
    end

    query = from(p in Post, join: pl in p.permalink, select: assoc(p, permalink: pl))
    assert_raise Ecto.QueryError, ~r"`assoc/2` selector requires a primary key on", fn ->
      validate(query)
    end

    query = from(p in Post, join: c in Comment, on: true, select: assoc(p, comments: c))
    assert_raise Ecto.QueryError, ~r"can only associate on an inner or left association join", fn ->
      validate(query)
    end
  end

  test "source only query" do
    query = from(p in "posts", select: p.any_post)
    validate(query)
  end
end
