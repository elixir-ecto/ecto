Code.require_file "../support/types.exs", __DIR__

defmodule Ecto.Integration.SubQueryTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  import Ecto.Query
  alias Ecto.Integration.Post

  test "subqueries with select source" do
    TestRepo.insert!(%Post{text: "hello", public: true})

    query = from p in Post, select: p
    assert ["hello"] =
           TestRepo.all(from p in subquery(query), select: p.text)
    assert [%Post{inserted_at: %Ecto.DateTime{}}] =
           TestRepo.all(from p in subquery(query), select: p)
  end

  test "subqueries with select expression" do
    TestRepo.insert!(%Post{text: "hello", public: true})

    query = from p in Post, select: {p.text, p.public}
    assert ["hello"] =
           TestRepo.all(from p in subquery(query), select: p.text)
    assert [{"hello", true}] =
           TestRepo.all(from p in subquery(query), select: p)
    assert [{"hello", {"hello", true}}] =
           TestRepo.all(from p in subquery(query), select: {p.text, p})
    assert [{{"hello", true}, true}] =
           TestRepo.all(from p in subquery(query), select: {p, p.public})
  end

  test "subqueries with aggregates" do
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
end
