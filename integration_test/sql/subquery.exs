Code.require_file "../support/types.exs", __DIR__

defmodule Ecto.Integration.SubQueryTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  import Ecto.Query
  alias Ecto.Integration.Post
  alias Ecto.Integration.Comment

  test "from: subqueries with select source" do
    TestRepo.insert!(%Post{text: "hello", public: true})

    query = from p in Post, select: p
    assert ["hello"] =
           TestRepo.all(from p in subquery(query), select: p.text)
    assert [post] =
           TestRepo.all(from p in subquery(query), select: p)

    assert %NaiveDateTime{} = post.inserted_at
    assert post.__meta__.state == :loaded
  end

  test "from: subqueries with map and select expression" do
    TestRepo.insert!(%Post{text: "hello", public: true})

    query = from p in Post, select: %{text: p.text, pub: not p.public}
    assert ["hello"] =
           TestRepo.all(from p in subquery(query), select: p.text)
    assert [%{text: "hello", pub: false}] =
           TestRepo.all(from p in subquery(query), select: p)
    assert [{"hello", %{text: "hello", pub: false}}] =
           TestRepo.all(from p in subquery(query), select: {p.text, p})
    assert [{%{text: "hello", pub: false}, false}] =
           TestRepo.all(from p in subquery(query), select: {p, p.pub})
  end

  test "from: subqueries with map update and select expression" do
    TestRepo.insert!(%Post{text: "hello", public: true})

    query = from p in Post, select: %{p | public: not p.public}
    assert ["hello"] =
           TestRepo.all(from p in subquery(query), select: p.text)
    assert [%Post{text: "hello", public: false}] =
           TestRepo.all(from p in subquery(query), select: p)
    assert [{"hello", %Post{text: "hello", public: false}}] =
           TestRepo.all(from p in subquery(query), select: {p.text, p})
    assert [{%Post{text: "hello", public: false}, false}] =
           TestRepo.all(from p in subquery(query), select: {p, p.public})
  end

  test "from: subqueries with map update on virtual field and select expression" do
    TestRepo.insert!(%Post{text: "hello"})

    query = from p in Post, select: %{p | temp: p.text}
    assert ["hello"] =
           TestRepo.all(from p in subquery(query), select: p.temp)
    assert [%Post{text: "hello", temp: "hello"}] =
           TestRepo.all(from p in subquery(query), select: p)
  end

  test "from: subqueries with aggregates" do
    TestRepo.insert!(%Post{visits: 10})
    TestRepo.insert!(%Post{visits: 11})
    TestRepo.insert!(%Post{visits: 13})

    query = from p in Post, select: [:visits], order_by: [asc: :visits]
    assert [13] = TestRepo.all(from p in subquery(query), select: max(p.visits))
    query = from p in Post, select: [:visits], order_by: [asc: :visits], limit: 2
    assert [11] = TestRepo.all(from p in subquery(query), select: max(p.visits))

    query = from p in Post, order_by: [asc: :visits]
    assert [13] = TestRepo.all(from p in subquery(query), select: max(p.visits))
    query = from p in Post, order_by: [asc: :visits], limit: 2
    assert [11] = TestRepo.all(from p in subquery(query), select: max(p.visits))
  end

  test "from: subqueries with parameters" do
    TestRepo.insert!(%Post{visits: 10, text: "hello"})
    TestRepo.insert!(%Post{visits: 11, text: "hello"})
    TestRepo.insert!(%Post{visits: 13, text: "world"})

    query = from p in Post, where: p.visits >= ^11 and p.visits <= ^13
    query = from p in subquery(query), where: p.text == ^"hello", select: fragment("? + ?", p.visits, ^1)
    assert [12] = TestRepo.all(query)
  end

  test "join: subqueries with select source" do
    %{id: id} = TestRepo.insert!(%Post{text: "hello", public: true})
    TestRepo.insert!(%Comment{post_id: id})

    query = from p in Post, select: p
    assert ["hello"] =
           TestRepo.all(from c in Comment, join: p in subquery(query), on: c.post_id == p.id, select: p.text)
    assert [%Post{inserted_at: %NaiveDateTime{}}] =
           TestRepo.all(from c in Comment, join: p in subquery(query), on: c.post_id == p.id, select: p)
  end

  test "join: subqueries with parameters" do
    TestRepo.insert!(%Post{visits: 10, text: "hello"})
    TestRepo.insert!(%Post{visits: 11, text: "hello"})
    TestRepo.insert!(%Post{visits: 13, text: "world"})
    TestRepo.insert!(%Comment{})
    TestRepo.insert!(%Comment{})

    query = from p in Post, where: p.visits >= ^11 and p.visits <= ^13
    query = from c in Comment,
              join: p in subquery(query),
              where: p.text == ^"hello",
              select: fragment("? + ?", p.visits, ^1)
    assert [12, 12] = TestRepo.all(query)
  end
end
