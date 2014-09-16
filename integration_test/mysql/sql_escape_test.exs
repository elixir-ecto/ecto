defmodule Ecto.Integration.Mysql.SQLEscapeTest do
  use Ecto.Integration.Mysql.Case

  # MYSQL TODO: Fix this
  # test "Repo.all escape" do
  #   TestRepo.create(%Post{text: "hello"))

  #   query = from(p in Post, select: "'\\")
  #   assert ["'\\"] == TestRepo.all(query)
  # end


  test "Repo.create escape" do
    TestRepo.insert(%Post{text: "'"})

    query = from(p in Post, select: p.text)
    assert ["'"] == TestRepo.all(query)
  end

  test "Repo.update escape" do
    p = TestRepo.insert(%Post{text: "hello"})
    TestRepo.update(%{p | text: "'"})

    query = from(p in Post, select: p.text)
    assert ["'"] == TestRepo.all(query)
  end

  test "Repo.update_all escape" do
    TestRepo.insert(%Post{text: "hello"})
    TestRepo.update_all(Post, text: "'")

    query = from(p in Post, select: p.text)
    assert ["'"] == TestRepo.all(query)

    TestRepo.update_all(from(Post, where: "'" != ""), text: "''")
    assert ["''"] == TestRepo.all(query)
  end

  test "Repo.delete_all escape" do
    TestRepo.insert(%Post{text: "hello"})
    assert [_] = TestRepo.all(Post)

    TestRepo.delete_all(from(Post, where: "'" == "'"))
    assert [] == TestRepo.all(Post)
  end
end
