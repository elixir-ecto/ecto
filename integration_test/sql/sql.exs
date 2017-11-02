defmodule Ecto.Integration.SQLTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Barebone
  alias Ecto.Integration.Post
  alias Ecto.Integration.CorruptedPk
  import Ecto.Query, only: [from: 2]

  test "fragmented types" do
    datetime = ~N[2014-01-16 20:26:51]
    TestRepo.insert!(%Post{inserted_at: datetime})
    query = from p in Post, where: fragment("? >= ?", p.inserted_at, ^datetime), select: p.inserted_at
    assert [^datetime] = TestRepo.all(query)
  end

  test "fragmented schemaless types" do
    TestRepo.insert!(%Post{visits: 123})
    assert [123] = TestRepo.all(from p in "posts", select: type(fragment("visits"), :integer))
  end

  @tag :array_type
  test "fragment array types" do
    text1 = "foo"
    text2 = "bar"
    result = TestRepo.query!("SELECT $1::text[]", [[text1, text2]])
    assert result.rows == [[[text1, text2]]]
  end

  test "query!/4" do
    result = TestRepo.query!("SELECT 1")
    assert result.rows == [[1]]
  end

  test "query!/4 with iodata" do
    result = TestRepo.query!(["SELECT", ?\s, ?1])
    assert result.rows == [[1]]
  end

  test "to_sql/3" do
    {sql, []} = TestRepo.to_sql(:all, Barebone)
    assert sql =~ "SELECT"
    assert sql =~ "barebones"

    {sql, [0]} = TestRepo.to_sql(:update_all, from(b in Barebone, update: [set: [num: ^0]]))
    assert sql =~ "UPDATE"
    assert sql =~ "barebones"
    assert sql =~ "SET"

    {sql, []} = TestRepo.to_sql(:delete_all, Barebone)
    assert sql =~ "DELETE"
    assert sql =~ "barebones"
  end

  test "raises when primary key is not unique on struct operation" do
    schema = %CorruptedPk{a: "abc"}
    TestRepo.insert!(schema)
    TestRepo.insert!(schema)
    TestRepo.insert!(schema)

    assert_raise Ecto.MultiplePrimaryKeyError,
                 ~r|expected delete on corrupted_pk to return at most one entry but got 3 entries|,
                 fn -> TestRepo.delete!(schema) end
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

  @tag :insert_cell_wise_defaults
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

  test "load" do
    inserted_at = ~N[2016-01-01 09:00:00]
    TestRepo.insert!(%Post{title: "title1", inserted_at: inserted_at, public: false})

    result = Ecto.Adapters.SQL.query!(TestRepo, "SELECT * FROM posts", [])
    posts = Enum.map(result.rows, &TestRepo.load(Post, {result.columns, &1}))
    assert [%Post{title: "title1", inserted_at: ^inserted_at, public: false}] = posts
  end
end
