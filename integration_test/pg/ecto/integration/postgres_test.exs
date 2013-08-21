defmodule Ecto.Integration.PostgresTest do
  use Ecto.Integration.Postgres.Case

  import Ecto.Query
  alias Ecto.Integration.Postgres.TestRepo
  alias Ecto.Integration.Postgres.Post
  alias Ecto.Integration.Postgres.Comment

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

  test "custom functions" do
    assert Post[id: id1] = TestRepo.create(Post[title: "hi"])
    assert [id1*10] == TestRepo.all(from p in Post, select: custom(p.id))
  end

  test "virtual field" do
    assert Post[id: id] = TestRepo.create(Post[title: "1", text: "hai"])
    assert TestRepo.get(Post, id).temp == "temp"
  end

  test "preload" do
    p1 = TestRepo.create(Post[title: "1"])
    p2 = TestRepo.create(Post[title: "2"])
    p3 = TestRepo.create(Post[title: "3"])

    Comment[id: cid1] = TestRepo.create(Comment[text: "1", post_id: p1.id])
    Comment[id: cid2] = TestRepo.create(Comment[text: "2", post_id: p1.id])
    Comment[id: cid3] = TestRepo.create(Comment[text: "3", post_id: p2.id])
    Comment[id: cid4] = TestRepo.create(Comment[text: "4", post_id: p2.id])

    assert_raise Ecto.AssociationNotLoadedError, fn ->
      p1.comments.to_list
    end

    assert [p3, p1, p2] = Ecto.Preloader.run(TestRepo, [p3, p1, p2], :comments)
    assert [Comment[id: ^cid1], Comment[id: ^cid2]] = p1.comments.to_list
    assert [Comment[id: ^cid3], Comment[id: ^cid4]] = p2.comments.to_list
    assert [] = p3.comments.to_list
  end

  test "preload keyword query" do
    p1 = TestRepo.create(Post[title: "1"])
    p2 = TestRepo.create(Post[title: "2"])
    TestRepo.create(Post[title: "3"])

    Comment[id: cid1] = TestRepo.create(Comment[text: "1", post_id: p1.id])
    Comment[id: cid2] = TestRepo.create(Comment[text: "2", post_id: p1.id])
    Comment[id: cid3] = TestRepo.create(Comment[text: "3", post_id: p2.id])
    Comment[id: cid4] = TestRepo.create(Comment[text: "4", post_id: p2.id])

    query = from(p in Post, preload: [:comments], select: p)

    assert [p1, p2, p3] = TestRepo.all(query)
    assert [Comment[id: ^cid1], Comment[id: ^cid2]] = p1.comments.to_list
    assert [Comment[id: ^cid3], Comment[id: ^cid4]] = p2.comments.to_list
    assert [] = p3.comments.to_list

    query = from(p in Post, preload: [:comments], select: { 0, [p] })
    posts = TestRepo.all(query)
    [p1, p2, p3] = Enum.map(posts, fn { 0, [p] } -> p end)

    assert [Comment[id: ^cid1], Comment[id: ^cid2]] = p1.comments.to_list
    assert [Comment[id: ^cid3], Comment[id: ^cid4]] = p2.comments.to_list
    assert [] = p3.comments.to_list
  end

  test "row transform" do
    post = TestRepo.create(Post[title: "1", text: "hi"])
    query = from(p in Post, select: { p.title, [ p, { p.text } ] })
    [{ "1", [ ^post, { "hi" } ] }] = TestRepo.all(query)
  end

  test "join" do
    post = TestRepo.create(Post[title: "1", text: "hi"])
    comment = TestRepo.create(Comment[text: "hey"])
    query = from(p in Post, join: c in Comment, on: true, select: { p, c })
    [{ ^post, ^comment }] = TestRepo.all(query)
  end

  test "association join" do
    post = TestRepo.create(Post[title: "1", text: "hi"])
    c1 = TestRepo.create(Comment[text: "hey", post_id: post.id])
    c2 = TestRepo.create(Comment[text: "heya", post_id: post.id])

    query = from(p in Post, join: c in p.comments, select: { p, c })
    [{ ^post, ^c1 }, { ^post, ^c2 }] = TestRepo.all(query)
  end

  test "has_many queryable" do
    p1 = TestRepo.create(Post[title: "1"])
    p2 = TestRepo.create(Post[title: "1"])

    Comment[id: cid1] = TestRepo.create(Comment[text: "1", post_id: p1.id])
    Comment[id: cid2] = TestRepo.create(Comment[text: "2", post_id: p1.id])
    Comment[id: cid3] = TestRepo.create(Comment[text: "3", post_id: p2.id])

    query = from(c in p1.comments)
    assert [Comment[id: ^cid1], Comment[id: ^cid2]] = TestRepo.all(query)

    query = from(c in p2.comments)
    assert [Comment[id: ^cid3]] = TestRepo.all(query)

    query = from(c in p1.comments, where: c.text == "1")
    assert [Comment[id: ^cid1]] = TestRepo.all(query)
  end

  test "assoc selector" do
    p1 = TestRepo.create(Post[title: "1"])
    p2 = TestRepo.create(Post[title: "1"])

    Comment[id: cid1] = TestRepo.create(Comment[text: "1", post_id: p1.id])
    Comment[id: cid2] = TestRepo.create(Comment[text: "2", post_id: p1.id])
    Comment[id: cid3] = TestRepo.create(Comment[text: "3", post_id: p2.id])

    query = from(p in Post, join: c in p.comments, select: assoc(p, c))
    assert [post1, post2] = TestRepo.all(query)
    assert [Comment[id: ^cid1], Comment[id: ^cid2]] = post1.comments.to_list
    assert [Comment[id: ^cid3]] = post2.comments.to_list
  end
end
