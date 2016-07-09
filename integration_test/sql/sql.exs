defmodule Ecto.Integration.SQLTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Barebone
  alias Ecto.Integration.Post
  import Ecto.Query, only: [from: 2]

  test "fragmented types" do
    datetime = %Ecto.DateTime{year: 2014, month: 1, day: 16,
                              hour: 20, min: 26, sec: 51, usec: 0}
    TestRepo.insert!(%Post{inserted_at: datetime})
    query = from p in Post, where: fragment("? >= ?", p.inserted_at, ^datetime), select: p.inserted_at
    assert [^datetime] = TestRepo.all(query)
  end

  @tag :array_type
  test "fragment array types" do
    datetime1 = %Ecto.DateTime{year: 2014, month: 1, day: 16, hour: 0, min: 0, sec: 0, usec: 0}
    datetime2 = %Ecto.DateTime{year: 2014, month: 2, day: 16, hour: 0, min: 0, sec: 0, usec: 0}
    result = TestRepo.query!("SELECT $1::timestamp[]", [[datetime1, datetime2]])
    assert [[[{{2014, 1, 16}, _}, {{2014, 2, 16}, _}]]] = result.rows
  end

  test "query!/4" do
    result = TestRepo.query!("SELECT 1")
    assert result.rows == [[1]]
  end

  test "to_sql/3" do
    {sql, []} = Ecto.Adapters.SQL.to_sql(:all, TestRepo, Barebone)
    assert sql =~ "SELECT"
    assert sql =~ "barebones"

    {sql, [0]} = Ecto.Adapters.SQL.to_sql(:update_all, TestRepo,
                                          from(b in Barebone, update: [set: [num: ^0]]))
    assert sql =~ "UPDATE"
    assert sql =~ "barebones"
    assert sql =~ "SET"

    {sql, []} = Ecto.Adapters.SQL.to_sql(:delete_all, TestRepo, Barebone)
    assert sql =~ "DELETE"
    assert sql =~ "barebones"
  end

  test "Repo.insert! escape" do
    TestRepo.insert!(%Post{title: "'"})

    query = from(p in Post, select: p.title)
    assert ["'"] == TestRepo.all(query)
  end

  test "Repo.update! escape" do
    p = TestRepo.insert!(%Post{title: "hello"})
    TestRepo.update!(Ecto.Changeset.change p, title: "'")

    query = from(p in Post, select: p.title)
    assert ["'"] == TestRepo.all(query)
  end

  test "Repo.insert_all escape" do
    TestRepo.insert_all(Post, [%{title: "'"}])

    query = from(p in Post, select: p.title)
    assert ["'"] == TestRepo.all(query)
  end

  test "Repo.update_all escape" do
    TestRepo.insert!(%Post{title: "hello"})

    TestRepo.update_all(Post, set: [title: "'"])
    reader = from(p in Post, select: p.title)
    assert ["'"] == TestRepo.all(reader)

    query = from(Post, where: "'" != "")
    TestRepo.update_all(query, set: [title: "''"])
    assert ["''"] == TestRepo.all(reader)
  end

  test "Repo.delete_all escape" do
    TestRepo.insert!(%Post{title: "hello"})
    assert [_] = TestRepo.all(Post)

    TestRepo.delete_all(from(Post, where: "'" == "'"))
    assert [] == TestRepo.all(Post)
  end
end
