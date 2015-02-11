defmodule Ecto.Integration.SQLEscapeTest do
  use Ecto.Integration.Case

  require Ecto.Integration.TestRepo, as: TestRepo
  import Ecto.Query
  alias Ecto.Integration.Post

  test "Repo.all escape" do
    TestRepo.insert(%Post{title: "hello"})

    query = from(p in Post, select: "'\\")
    assert ["'\\"] == TestRepo.all(query)
  end

  test "Repo.insert escape" do
    TestRepo.insert(%Post{title: "'"})

    query = from(p in Post, select: p.title)
    assert ["'"] == TestRepo.all(query)
  end

  test "Repo.update escape" do
    p = TestRepo.insert(%Post{title: "hello"})
    TestRepo.update(%{p | title: "'"})

    query = from(p in Post, select: p.title)
    assert ["'"] == TestRepo.all(query)
  end

  test "Repo.update_all escape" do
    TestRepo.insert(%Post{title: "hello"})
    TestRepo.update_all(Post, title: "'")

    query = from(p in Post, select: p.title)
    assert ["'"] == TestRepo.all(query)

    TestRepo.update_all(from(Post, where: "'" != ""), title: "''")
    assert ["''"] == TestRepo.all(query)
  end

  test "Repo.delete_all escape" do
    TestRepo.insert(%Post{title: "hello"})
    assert [_] = TestRepo.all(Post)

    TestRepo.delete_all(from(Post, where: "'" == "'"))
    assert [] == TestRepo.all(Post)
  end
end
