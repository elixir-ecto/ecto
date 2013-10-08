defmodule Ecto.Integration.PostgresTest do
  use Ecto.Integration.Postgres.Case

  test "fetch empty" do
    assert [] == TestRepo.all(from p in Post)
  end

  test "create and fetch single" do
    assert Post.Entity[id: id] = TestRepo.create(Post.Entity[title: "The shiny new Ecto", text: "coming soon..."])

    assert is_integer(id)

    assert [Post.Entity[id: ^id, title: "The shiny new Ecto", text: "coming soon..."]] =
           TestRepo.all(from p in Post)
  end

  test "create and delete single, fetch nothing" do
    post = Post.Entity[title: "The shiny new Ecto", text: "coming soon..."]

    assert Post.Entity[] = created = TestRepo.create(post)
    assert :ok == TestRepo.delete(created)

    assert [] = TestRepo.all(from p in Post)
  end

  test "create and delete single, fetch empty" do
    post = Post.Entity[title: "The shiny new Ecto", text: "coming soon..."]

    assert Post.Entity[] = TestRepo.create(post)
    assert Post.Entity[] = created = TestRepo.create(post)
    assert :ok == TestRepo.delete(created)

    assert [Post.Entity[]] = TestRepo.all(from p in Post)
  end

  test "create and update single, fetch updated" do
    post = Post.Entity[title: "The shiny new Ecto", text: "coming soon..."]

    post = TestRepo.create(post)
    post = post.text("coming very soon...")
    assert :ok == TestRepo.update(post)

    assert [Post.Entity[text: "coming very soon..."]] = TestRepo.all(from p in Post)
  end

  test "create and fetch multiple" do
    assert Post.Entity[] = TestRepo.create(Post.Entity[title: "1", text: "hai"])
    assert Post.Entity[] = TestRepo.create(Post.Entity[title: "2", text: "hai"])
    assert Post.Entity[] = TestRepo.create(Post.Entity[title: "3", text: "hai"])

    assert [Post.Entity[title: "1"], Post.Entity[title: "2"], Post.Entity[title: "3"]] =
           TestRepo.all(from p in Post)

    assert [Post.Entity[title: "2"]] =
           TestRepo.all(from p in Post, where: p.title == "2")
  end

  test "get entity" do
    post1 = TestRepo.create(Post.Entity[title: "1", text: "hai"])
    post2 = TestRepo.create(Post.Entity[title: "2", text: "hai"])

    assert post1 == TestRepo.get(Post, post1.id)
    assert post2 == TestRepo.get(Post, post2.id)
    assert nil == TestRepo.get(Post, -1)
  end

  test "transform row" do
    assert Post.Entity[] = TestRepo.create(Post.Entity[title: "1", text: "hai"])

    assert ["1"] == TestRepo.all(from p in Post, select: p.title)

    assert [{ "1", "hai" }] ==
           TestRepo.all(from p in Post, select: { p.title, p.text })

    assert [["1", "hai"]] ==
           TestRepo.all(from p in Post, select: [p.title, p.text])
  end

  test "update some entites" do
    assert Post.Entity[id: id1] = TestRepo.create(Post.Entity[title: "1", text: "hai"])
    assert Post.Entity[id: id2] = TestRepo.create(Post.Entity[title: "2", text: "hai"])
    assert Post.Entity[id: id3] = TestRepo.create(Post.Entity[title: "3", text: "hai"])

    query = from(p in Post, where: p.title == "1" or p.title == "2")
    assert 2 = TestRepo.update_all(query, title: "x")
    assert Post.Entity[title: "x"] = TestRepo.get(Post, id1)
    assert Post.Entity[title: "x"] = TestRepo.get(Post, id2)
    assert Post.Entity[title: "3"] = TestRepo.get(Post, id3)
  end

  test "update all entites" do
    assert Post.Entity[id: id1] = TestRepo.create(Post.Entity[title: "1", text: "hai"])
    assert Post.Entity[id: id2] = TestRepo.create(Post.Entity[title: "2", text: "hai"])
    assert Post.Entity[id: id3] = TestRepo.create(Post.Entity[title: "3", text: "hai"])

    assert 3 = TestRepo.update_all(Post, title: "x")
    assert Post.Entity[title: "x"] = TestRepo.get(Post, id1)
    assert Post.Entity[title: "x"] = TestRepo.get(Post, id2)
    assert Post.Entity[title: "x"] = TestRepo.get(Post, id3)
  end

  test "update no entites" do
    assert Post.Entity[id: id1] = TestRepo.create(Post.Entity[title: "1", text: "hai"])
    assert Post.Entity[id: id2] = TestRepo.create(Post.Entity[title: "2", text: "hai"])
    assert Post.Entity[id: id3] = TestRepo.create(Post.Entity[title: "3", text: "hai"])

    query = from(p in Post, where: p.title == "4")
    assert 0 = TestRepo.update_all(query, title: "x")
    assert Post.Entity[title: "1"] = TestRepo.get(Post, id1)
    assert Post.Entity[title: "2"] = TestRepo.get(Post, id2)
    assert Post.Entity[title: "3"] = TestRepo.get(Post, id3)
  end

  test "update expression syntax" do
    assert Post.Entity[id: id1] = TestRepo.create(Post.Entity[title: "1", text: "hai", count: 1])
    assert Post.Entity[id: id2] = TestRepo.create(Post.Entity[title: "2", text: "hai", count: 1])

    assert 2 = TestRepo.update_all(p in Post, count: p.count + 41)
    assert Post.Entity[count: 42] = TestRepo.get(Post, id1)
    assert Post.Entity[count: 42] = TestRepo.get(Post, id2)
  end

  test "delete some entites" do
    assert Post.Entity[] = TestRepo.create(Post.Entity[title: "1", text: "hai"])
    assert Post.Entity[] = TestRepo.create(Post.Entity[title: "2", text: "hai"])
    assert Post.Entity[] = TestRepo.create(Post.Entity[title: "3", text: "hai"])

    query = from(p in Post, where: p.title == "1" or p.title == "2")
    assert 2 = TestRepo.delete_all(query)
    assert [Post.Entity[]] = TestRepo.all(Post)
  end

  test "delete all entites" do
    assert Post.Entity[] = TestRepo.create(Post.Entity[title: "1", text: "hai"])
    assert Post.Entity[] = TestRepo.create(Post.Entity[title: "2", text: "hai"])
    assert Post.Entity[] = TestRepo.create(Post.Entity[title: "3", text: "hai"])

    assert 3 = TestRepo.delete_all(Post)
    assert [] = TestRepo.all(Post)
  end

  test "delete no entites" do
    assert Post.Entity[id: id1] = TestRepo.create(Post.Entity[title: "1", text: "hai"])
    assert Post.Entity[id: id2] = TestRepo.create(Post.Entity[title: "2", text: "hai"])
    assert Post.Entity[id: id3] = TestRepo.create(Post.Entity[title: "3", text: "hai"])

    query = from(p in Post, where: p.title == "4")
    assert 0 = TestRepo.delete_all(query)
    assert Post.Entity[title: "1"] = TestRepo.get(Post, id1)
    assert Post.Entity[title: "2"] = TestRepo.get(Post, id2)
    assert Post.Entity[title: "3"] = TestRepo.get(Post, id3)
  end

  test "custom functions" do
    assert Post.Entity[id: id1] = TestRepo.create(Post.Entity[title: "hi"])
    assert [id1*10] == TestRepo.all(from p in Post, select: custom(p.id))
  end

  test "virtual field" do
    assert Post.Entity[id: id] = TestRepo.create(Post.Entity[title: "1", text: "hai"])
    assert TestRepo.get(Post, id).temp == "temp"
  end

  test "preload has_many" do
    p1 = TestRepo.create(Post.Entity[title: "1"])
    p2 = TestRepo.create(Post.Entity[title: "2"])
    p3 = TestRepo.create(Post.Entity[title: "3"])

    Comment.Entity[id: cid1] = TestRepo.create(Comment.Entity[text: "1", post_id: p1.id])
    Comment.Entity[id: cid2] = TestRepo.create(Comment.Entity[text: "2", post_id: p1.id])
    Comment.Entity[id: cid3] = TestRepo.create(Comment.Entity[text: "3", post_id: p2.id])
    Comment.Entity[id: cid4] = TestRepo.create(Comment.Entity[text: "4", post_id: p2.id])

    assert_raise Ecto.AssociationNotLoadedError, fn ->
      p1.comments.to_list
    end

    assert [p3, p1, p2] = Ecto.Preloader.run(TestRepo, [p3, p1, p2], :comments)
    assert [Comment.Entity[id: ^cid1], Comment.Entity[id: ^cid2]] = p1.comments.to_list
    assert [Comment.Entity[id: ^cid3], Comment.Entity[id: ^cid4]] = p2.comments.to_list
    assert [] = p3.comments.to_list
  end

  test "preload has_one" do
    p1 = TestRepo.create(Post.Entity[title: "1"])
    p2 = TestRepo.create(Post.Entity[title: "2"])
    p3 = TestRepo.create(Post.Entity[title: "3"])

    Permalink.Entity[id: pid1] = TestRepo.create(Permalink.Entity[url: "1", post_id: p1.id])
    Permalink.Entity[]         = TestRepo.create(Permalink.Entity[url: "2", post_id: nil])
    Permalink.Entity[id: pid3] = TestRepo.create(Permalink.Entity[url: "3", post_id: p3.id])

    assert_raise Ecto.AssociationNotLoadedError, fn ->
      p1.permalink.get
    end
    assert_raise Ecto.AssociationNotLoadedError, fn ->
      p2.permalink.get
    end

    assert [p3, p1, p2] = Ecto.Preloader.run(TestRepo, [p3, p1, p2], :permalink)
    assert Permalink.Entity[id: ^pid1] = p1.permalink.get
    assert nil = p2.permalink.get
    assert Permalink.Entity[id: ^pid3] = p3.permalink.get
  end

  test "preload belongs_to" do
    Post.Entity[id: pid1] = TestRepo.create(Post.Entity[title: "1"])
    TestRepo.create(Post.Entity[title: "2"])
    Post.Entity[id: pid3] = TestRepo.create(Post.Entity[title: "3"])

    pl1 = TestRepo.create(Permalink.Entity[url: "1", post_id: pid1])
    pl2 = TestRepo.create(Permalink.Entity[url: "2", post_id: nil])
    pl3 = TestRepo.create(Permalink.Entity[url: "3", post_id: pid3])

    assert_raise Ecto.AssociationNotLoadedError, fn ->
      pl1.post.get
    end

    assert [pl3, pl1, pl2] = Ecto.Preloader.run(TestRepo, [pl3, pl1, pl2], :post)
    assert Post.Entity[id: ^pid1] = pl1.post.get
    assert nil = pl2.post.get
    assert Post.Entity[id: ^pid3] = pl3.post.get
  end

  test "preload belongs_to with shared assocs 1" do
    Post.Entity[id: pid1] = TestRepo.create(Post.Entity[title: "1"])
    Post.Entity[id: pid2] = TestRepo.create(Post.Entity[title: "2"])

    c1 = TestRepo.create(Comment.Entity[text: "1", post_id: pid1])
    c2 = TestRepo.create(Comment.Entity[text: "2", post_id: pid1])
    c3 = TestRepo.create(Comment.Entity[text: "3", post_id: pid2])

    assert [c3, c1, c2] = Ecto.Preloader.run(TestRepo, [c3, c1, c2], :post)
    assert Post.Entity[id: ^pid1] = c1.post.get
    assert Post.Entity[id: ^pid1] = c2.post.get
    assert Post.Entity[id: ^pid2] = c3.post.get
  end

  test "preload belongs_to with shared assocs 2" do
    Post.Entity[id: pid1] = TestRepo.create(Post.Entity[title: "1"])
    Post.Entity[id: pid2] = TestRepo.create(Post.Entity[title: "2"])

    c1 = TestRepo.create(Comment.Entity[text: "1", post_id: pid1])
    c2 = TestRepo.create(Comment.Entity[text: "2", post_id: pid2])
    c3 = TestRepo.create(Comment.Entity[text: "3", post_id: nil])

    assert [c3, c1, c2] = Ecto.Preloader.run(TestRepo, [c3, c1, c2], :post)
    assert Post.Entity[id: ^pid1] = c1.post.get
    assert Post.Entity[id: ^pid2] = c2.post.get
    assert nil = c3.post.get
  end

  test "preload keyword query" do
    p1 = TestRepo.create(Post.Entity[title: "1"])
    p2 = TestRepo.create(Post.Entity[title: "2"])
    TestRepo.create(Post.Entity[title: "3"])

    Comment.Entity[id: cid1] = TestRepo.create(Comment.Entity[text: "1", post_id: p1.id])
    Comment.Entity[id: cid2] = TestRepo.create(Comment.Entity[text: "2", post_id: p1.id])
    Comment.Entity[id: cid3] = TestRepo.create(Comment.Entity[text: "3", post_id: p2.id])
    Comment.Entity[id: cid4] = TestRepo.create(Comment.Entity[text: "4", post_id: p2.id])

    query = from(p in Post, preload: [:comments], select: p)

    assert [p1, p2, p3] = TestRepo.all(query)
    assert [Comment.Entity[id: ^cid1], Comment.Entity[id: ^cid2]] = p1.comments.to_list
    assert [Comment.Entity[id: ^cid3], Comment.Entity[id: ^cid4]] = p2.comments.to_list
    assert [] = p3.comments.to_list

    query = from(p in Post, preload: [:comments], select: { 0, [p] })
    posts = TestRepo.all(query)
    [p1, p2, p3] = Enum.map(posts, fn { 0, [p] } -> p end)

    assert [Comment.Entity[id: ^cid1], Comment.Entity[id: ^cid2]] = p1.comments.to_list
    assert [Comment.Entity[id: ^cid3], Comment.Entity[id: ^cid4]] = p2.comments.to_list
    assert [] = p3.comments.to_list
  end

  test "preload nils" do
    p1 = TestRepo.create(Post.Entity[title: "1"])
    p2 = TestRepo.create(Post.Entity[title: "2"])

    assert [Post.Entity[], nil, Post.Entity[]] = Ecto.Preloader.run(TestRepo, [p1, nil, p2], :permalink)
  end

  test "row transform" do
    post = TestRepo.create(Post.Entity[title: "1", text: "hi"])
    query = from(p in Post, select: { p.title, [ p, { p.text } ] })
    [{ "1", [ ^post, { "hi" } ] }] = TestRepo.all(query)
  end

  test "join" do
    post = TestRepo.create(Post.Entity[title: "1", text: "hi"])
    comment = TestRepo.create(Comment.Entity[text: "hey"])
    query = from(p in Post, join: c in Comment, on: true, select: { p, c })
    [{ ^post, ^comment }] = TestRepo.all(query)
  end

  test "has_many association join" do
    post = TestRepo.create(Post.Entity[title: "1", text: "hi"])
    c1 = TestRepo.create(Comment.Entity[text: "hey", post_id: post.id])
    c2 = TestRepo.create(Comment.Entity[text: "heya", post_id: post.id])

    query = from(p in Post, join: c in p.comments, select: { p, c })
    [{ ^post, ^c1 }, { ^post, ^c2 }] = TestRepo.all(query)
  end

  test "has_one association join" do
    post = TestRepo.create(Post.Entity[title: "1", text: "hi"])
    p1 = TestRepo.create(Permalink.Entity[url: "hey", post_id: post.id])
    p2 = TestRepo.create(Permalink.Entity[url: "heya", post_id: post.id])

    query = from(p in Post, join: c in p.permalink, select: { p, c })
    [{ ^post, ^p1 }, { ^post, ^p2 }] = TestRepo.all(query)
  end

  test "belongs_to association join" do
    post = TestRepo.create(Post.Entity[title: "1", text: "hi"])
    p1 = TestRepo.create(Permalink.Entity[url: "hey", post_id: post.id])
    p2 = TestRepo.create(Permalink.Entity[url: "heya", post_id: post.id])

    query = from(p in Permalink, join: c in p.post, select: { p, c })
    [{ ^p1, ^post }, { ^p2, ^post }] = TestRepo.all(query)
  end

  test "has_many queryable" do
    p1 = TestRepo.create(Post.Entity[title: "1"])
    p2 = TestRepo.create(Post.Entity[title: "1"])

    Comment.Entity[id: cid1] = TestRepo.create(Comment.Entity[text: "1", post_id: p1.id])
    Comment.Entity[id: cid2] = TestRepo.create(Comment.Entity[text: "2", post_id: p1.id])
    Comment.Entity[id: cid3] = TestRepo.create(Comment.Entity[text: "3", post_id: p2.id])

    query = from(c in p1.comments)
    assert [Comment.Entity[id: ^cid1], Comment.Entity[id: ^cid2]] = TestRepo.all(query)

    query = from(c in p2.comments)
    assert [Comment.Entity[id: ^cid3]] = TestRepo.all(query)

    query = from(c in p1.comments, where: c.text == "1")
    assert [Comment.Entity[id: ^cid1]] = TestRepo.all(query)
  end

  test "has_many assoc selector" do
    p1 = TestRepo.create(Post.Entity[title: "1"])
    p2 = TestRepo.create(Post.Entity[title: "1"])

    Comment.Entity[id: cid1] = TestRepo.create(Comment.Entity[text: "1", post_id: p1.id])
    Comment.Entity[id: cid2] = TestRepo.create(Comment.Entity[text: "2", post_id: p1.id])
    Comment.Entity[id: cid3] = TestRepo.create(Comment.Entity[text: "3", post_id: p2.id])

    query = from(p in Post, join: c in p.comments, select: assoc(p, c))
    assert [post1, post2] = TestRepo.all(query)
    assert [Comment.Entity[id: ^cid1], Comment.Entity[id: ^cid2]] = post1.comments.to_list
    assert [Comment.Entity[id: ^cid3]] = post2.comments.to_list
  end

  test "has_one assoc selector" do
    p1 = TestRepo.create(Post.Entity[title: "1"])
    p2 = TestRepo.create(Post.Entity[title: "2"])

    Permalink.Entity[id: pid1] = TestRepo.create(Permalink.Entity[url: "1", post_id: p1.id])
    Permalink.Entity[]         = TestRepo.create(Permalink.Entity[url: "2"])
    Permalink.Entity[id: pid3] = TestRepo.create(Permalink.Entity[url: "3", post_id: p2.id])

    query = from(p in Post, join: c in p.permalink, select: assoc(p, c))
    assert [post1, post3] = TestRepo.all(query)
    assert Permalink.Entity[id: ^pid1] = post1.permalink.get
    assert Permalink.Entity[id: ^pid3] = post3.permalink.get
  end

  test "belongs_to assoc selector" do
    Post.Entity[id: pid1] = TestRepo.create(Post.Entity[title: "1"])
    Post.Entity[id: pid2] = TestRepo.create(Post.Entity[title: "2"])

    TestRepo.create(Permalink.Entity[url: "1", post_id: pid1])
    TestRepo.create(Permalink.Entity[url: "2"])
    TestRepo.create(Permalink.Entity[url: "3", post_id: pid2])

    query = from(p in Permalink, left_join: c in p.post, select: assoc(p, c))
    assert [p1, p2, p3] = TestRepo.all(query)
    assert Post.Entity[id: ^pid1] = p1.post.get
    assert nil = p2.post.get
    assert Post.Entity[id: ^pid2] = p3.post.get
  end

  test "belongs_to assoc selector with shared assoc" do
    Post.Entity[id: pid1] = TestRepo.create(Post.Entity[title: "1"])
    Post.Entity[id: pid2] = TestRepo.create(Post.Entity[title: "2"])

    c1 = TestRepo.create(Comment.Entity[text: "1", post_id: pid1])
    c2 = TestRepo.create(Comment.Entity[text: "2", post_id: pid1])
    c3 = TestRepo.create(Comment.Entity[text: "3", post_id: pid2])

    query = from(c in Comment, join: p in c.post, select: assoc(c, p))
    assert [c1, c2, c3] = TestRepo.all(query)
    assert Post.Entity[id: ^pid1] = c1.post.get
    assert Post.Entity[id: ^pid1] = c2.post.get
    assert Post.Entity[id: ^pid2] = c3.post.get
  end

  test "belongs_to assoc selector with shared assoc 2" do
    Post.Entity[id: pid1] = TestRepo.create(Post.Entity[title: "1"])
    Post.Entity[id: pid2] = TestRepo.create(Post.Entity[title: "2"])

    c1 = TestRepo.create(Comment.Entity[text: "1", post_id: pid1])
    c2 = TestRepo.create(Comment.Entity[text: "2", post_id: pid2])
    c3 = TestRepo.create(Comment.Entity[text: "3", post_id: nil])

    query = from(c in Comment, left_join: p in c.post, select: assoc(c, p))
    assert [c1, c2, c3] = TestRepo.all(query)
    assert Post.Entity[id: ^pid1] = c1.post.get
    assert Post.Entity[id: ^pid2] = c2.post.get
    assert nil = c3.post.get
  end

  test "join qualifier" do
    p1 = TestRepo.create(Post.Entity[title: "1"])
    p2 = TestRepo.create(Post.Entity[title: "2"])
    c1 = TestRepo.create(Permalink.Entity[url: "1", post_id: p2.id])

    query = from(p in Post, left_join: c in p.permalink, order_by: p.id, select: {p, c})
    assert [{^p1, nil}, {^p2, ^c1}] = TestRepo.all(query)
  end

  test "datetime type" do
    now = Ecto.DateTime[year: 2013, month: 8, day: 1, hour: 14, min: 28, sec: 0]
    c = TestRepo.create(Comment.Entity[posted: now])

    assert Comment.Entity[posted: ^now] = TestRepo.get(Comment, c.id)
  end

  test "migrations test" do
    defmodule EctoMigrations do
      def up do
        "CREATE TABLE IF NOT EXISTS migrations_test(id serial primary key, name varchar(25))"
      end

      def down do
        "DROP table migrations_test"
      end
    end

    import Ecto.Migrator

    assert up(TestRepo, 20080906120000, EctoMigrations) == :ok
    assert up(TestRepo, 20080906120000, EctoMigrations) == :already_up
    assert down(TestRepo, 20080906120001, EctoMigrations) == :missing_up
    assert down(TestRepo, 20080906120000, EctoMigrations) == :ok
  end

  test "mix ecto.migrate test" do
    assert (Mix.Tasks.Ecto.Migrate.run([Ecto.Integration.Postgres.TestRepo]) == [1])
    assert (Mix.Tasks.Ecto.Migrate.run([Ecto.Integration.Postgres.TestRepo]) == [])
  end

end
