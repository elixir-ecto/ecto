Code.require_file "../../test_helper.exs", __DIR__

defmodule Ecto.Adapters.PostgresTest do
  use Ecto.PgTest.Case

  import Ecto.Query

  test "fetch empty" do
    assert [] == TestRepo.all(from p in Post)
  end

  test "create and fetch single" do
    assert Post[id: id] = TestRepo.create(Post[title: "The shiny new Ecto", text: "coming soon..."])

    assert is_integer(id)

    assert [Post[id: ^id, title: "The shiny new Ecto", text: "coming soon..."]] =
           TestRepo.all(from p in Post)
  end

  test "create and delete single, fetch nothing" do
    post = Post[title: "The shiny new Ecto", text: "coming soon..."]

    assert Post[] = created = TestRepo.create(post)
    assert :ok == TestRepo.delete(created)

    assert [] = TestRepo.all(from p in Post)
  end

  test "create and delete single, fetch empty" do
    post = Post[title: "The shiny new Ecto", text: "coming soon..."]

    assert Post[] = TestRepo.create(post)
    assert Post[] = created = TestRepo.create(post)
    assert :ok == TestRepo.delete(created)

    assert [Post[]] = TestRepo.all(from p in Post)
  end

  test "create and update single, fetch updated" do
    post = Post[title: "The shiny new Ecto", text: "coming soon..."]

    post = TestRepo.create(post)
    post = post.text("coming very soon...")
    assert :ok == TestRepo.update(post)

    assert [Post[text: "coming very soon..."]] = TestRepo.all(from p in Post)
  end

  test "create and fetch multiple" do
    assert Post[] = TestRepo.create(Post[title: "1", text: "hai"])
    assert Post[] = TestRepo.create(Post[title: "2", text: "hai"])
    assert Post[] = TestRepo.create(Post[title: "3", text: "hai"])

    assert [Post[title: "1"], Post[title: "2"], Post[title: "3"]] =
           TestRepo.all(from p in Post)

    assert [Post[title: "2"]] =
           TestRepo.all(from p in Post, where: p.title == "2")
  end

  test "get entity" do
    post1 = TestRepo.create(Post[title: "1", text: "hai"])
    post2 = TestRepo.create(Post[title: "2", text: "hai"])

    assert post1 == TestRepo.get(Post, post1.id)
    assert post2 == TestRepo.get(Post, post2.id)
    assert nil == TestRepo.get(Post, -1)
  end

  test "transform row" do
    assert Post[] = TestRepo.create(Post[title: "1", text: "hai"])

    assert ["1"] == TestRepo.all(from p in Post, select: p.title)

    assert [{ "1", "hai" }] ==
           TestRepo.all(from p in Post, select: { p.title, p.text })

    assert [["1", "hai"]] ==
           TestRepo.all(from p in Post, select: [p.title, p.text])
  end

  test "update some entites" do
    assert Post[id: id1] = TestRepo.create(Post[title: "1", text: "hai"])
    assert Post[id: id2] = TestRepo.create(Post[title: "2", text: "hai"])
    assert Post[id: id3] = TestRepo.create(Post[title: "3", text: "hai"])

    query = from(p in Post, where: p.title == "1" or p.title == "2")
    assert 2 = TestRepo.update_all(query, title: "x")
    assert Post[title: "x"] = TestRepo.get(Post, id1)
    assert Post[title: "x"] = TestRepo.get(Post, id2)
    assert Post[title: "3"] = TestRepo.get(Post, id3)
  end

  test "update all entites" do
    assert Post[id: id1] = TestRepo.create(Post[title: "1", text: "hai"])
    assert Post[id: id2] = TestRepo.create(Post[title: "2", text: "hai"])
    assert Post[id: id3] = TestRepo.create(Post[title: "3", text: "hai"])

    assert 3 = TestRepo.update_all(Post, title: "x")
    assert Post[title: "x"] = TestRepo.get(Post, id1)
    assert Post[title: "x"] = TestRepo.get(Post, id2)
    assert Post[title: "x"] = TestRepo.get(Post, id3)
  end

  test "update no entites" do
    assert Post[id: id1] = TestRepo.create(Post[title: "1", text: "hai"])
    assert Post[id: id2] = TestRepo.create(Post[title: "2", text: "hai"])
    assert Post[id: id3] = TestRepo.create(Post[title: "3", text: "hai"])

    query = from(p in Post, where: p.title == "4")
    assert 0 = TestRepo.update_all(query, title: "x")
    assert Post[title: "1"] = TestRepo.get(Post, id1)
    assert Post[title: "2"] = TestRepo.get(Post, id2)
    assert Post[title: "3"] = TestRepo.get(Post, id3)
  end

  test "update expression syntax" do
    assert Post[id: id1] = TestRepo.create(Post[title: "1", text: "hai", count: 1])
    assert Post[id: id2] = TestRepo.create(Post[title: "2", text: "hai", count: 1])

    assert 2 = TestRepo.update_all(p in Post, count: p.count + 41)
    assert Post[count: 42] = TestRepo.get(Post, id1)
    assert Post[count: 42] = TestRepo.get(Post, id2)
  end

  test "delete some entites" do
    assert Post[] = TestRepo.create(Post[title: "1", text: "hai"])
    assert Post[] = TestRepo.create(Post[title: "2", text: "hai"])
    assert Post[] = TestRepo.create(Post[title: "3", text: "hai"])

    query = from(p in Post, where: p.title == "1" or p.title == "2")
    assert 2 = TestRepo.delete_all(query)
    assert [Post[]] = TestRepo.all(Post)
  end

  test "delete all entites" do
    assert Post[] = TestRepo.create(Post[title: "1", text: "hai"])
    assert Post[] = TestRepo.create(Post[title: "2", text: "hai"])
    assert Post[] = TestRepo.create(Post[title: "3", text: "hai"])

    assert 3 = TestRepo.delete_all(Post)
    assert [] = TestRepo.all(Post)
  end

  test "delete no entites" do
    assert Post[id: id1] = TestRepo.create(Post[title: "1", text: "hai"])
    assert Post[id: id2] = TestRepo.create(Post[title: "2", text: "hai"])
    assert Post[id: id3] = TestRepo.create(Post[title: "3", text: "hai"])

    query = from(p in Post, where: p.title == "4")
    assert 0 = TestRepo.delete_all(query)
    assert Post[title: "1"] = TestRepo.get(Post, id1)
    assert Post[title: "2"] = TestRepo.get(Post, id2)
    assert Post[title: "3"] = TestRepo.get(Post, id3)
  end
end
