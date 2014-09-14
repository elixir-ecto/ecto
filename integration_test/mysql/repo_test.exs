defmodule Ecto.Integration.RepoTest do
  use Ecto.Integration.Mysql.Case

  alias Ecto.Associations.Preloader

  test "types" do
    TestRepo.insert(%Post{})

    # MySQL doesn't preserve boolean type. they are essentially just tinyints
    assert [{ 1, 0 }] ==
           TestRepo.all(from Post, select: { true, false })

    assert [{ 1, 2.0 }] ==
           TestRepo.all(from Post, select: { 1, 2.0 })

    assert [{ "abc", << 0, 1 >> }] ==
           TestRepo.all(from Post, select: { "abc", binary(^<< 0 , 1 >>) })

    # this query is wonky. throws exception because DateTime isn't converted for some reason.
    # postgres adapter has Postgrex encoders/decoders for it. seems to need more decoupling from dependency
    #assert [{ %Ecto.DateTime{year: 2014, month: 1, day: 16, hour: 20, min: 26, sec: 51} }] ==
           #TestRepo.all(from Post, select: { ^%Ecto.DateTime{year: 2014, month: 1, day: 16, hour: 20, min: 26, sec: 51} })

    # there is no interval type in mysql
    #assert [{ %Ecto.Interval{year: 0, month: 24169, day: 16, hour: 0, min: 0, sec: 73611} }] ==
           #TestRepo.all(from Post, select: { ^%Ecto.Interval{year: 2014, month: 1, day: 16, hour: 20, min: 26, sec: 51} })
  end

  test "returns already started for started repos" do
    assert { :error, { :already_started, _ } } = TestRepo.start_link
  end

  test "fetch empty" do
    assert [] == TestRepo.all(Post)
  end

  test "create and fetch single" do
    assert %Post{id: id} = TestRepo.insert(%Post{title: "create", text: "and fetch single"})

    assert is_integer(id)

    assert [%Post{id: ^id, title: "create", text: "and fetch single"}] =
           TestRepo.all(Post)

    assert %Post{id: ^id, title: "create", text: "and fetch single"} = TestRepo.one(Post)
  end

  test "fetch without model" do
    %Post{id: id} = TestRepo.insert(%Post{title: "title1"})
    %Post{} = TestRepo.insert(%Post{title: "title2"})

    assert ["title1", "title2"] =
      TestRepo.all(from(p in "posts", order_by: p.title, select: p.title))

    assert [^id] =
      TestRepo.all(from(p in "posts", where: p.title == "title1", select: p.id))

    assert "title1" =
      TestRepo.one(from(p in "posts", order_by: p.title, select: p.title, limit: 1))

    assert "title1" =
      TestRepo.one!(from(p in "posts", order_by: p.title, select: p.title, limit: 1))
  end

  test "create and delete single, fetch nothing" do
    post = %Post{title: "create and delete single", text: "fetch nothing"}

    assert %Post{} = created = TestRepo.insert(post)
    assert :ok == TestRepo.delete(created)

    assert [] = TestRepo.all(Post)
  end

  test "create and delete single, fetch empty" do
    post = %Post{title: "create and delete single", text: "fetch empty"}

    assert %Post{} = TestRepo.insert(post)
    assert %Post{} = created = TestRepo.insert(post)
    assert :ok == TestRepo.delete(created)

    assert [%Post{}] = TestRepo.all(Post)
  end

  test "create and update single, fetch updated" do
    post = %Post{title: "create and update single", text: "fetch updated", bin: <<1>>}

    post = TestRepo.insert(post)
    assert %Post{bin: <<1>>} = post
    post = %{post | text: "coming very soon..."}
    assert :ok == TestRepo.update(post)

    assert [%Post{text: "coming very soon...", bin: <<1>>}] = TestRepo.all(Post)
  end

  test "create and fetch multiple" do
    assert %Post{} = TestRepo.insert(%Post{title: "1", text: "hai"})
    assert %Post{} = TestRepo.insert(%Post{title: "2", text: "hai"})
    assert %Post{} = TestRepo.insert(%Post{title: "3", text: "hai"})

    assert [%Post{title: "1"}, %Post{title: "2"}, %Post{title: "3"}] =
           TestRepo.all(from p in Post, [])

    assert [%Post{title: "2"}] =
           TestRepo.all(from p in Post, where: p.title == "2")
  end

  test "create with no primary key" do
    assert %Barebone{text: nil} = TestRepo.insert(%Barebone{})
    assert %Barebone{text: "text"} = TestRepo.insert(%Barebone{text: "text"})
  end

  #test "create with user-assigned primary key" do
    #assert %AssignedPrimaryKey{id: "id"} = TestRepo.insert(%AssignedPrimaryKey{id: "id"})
    #assert_raise Mysql.Error, fn -> TestRepo.insert(%AssignedPrimaryKey{}) end
  #end

  test "get model" do
    post1 = TestRepo.insert(%Post{title: "1", text: "hai"})
    post2 = TestRepo.insert(%Post{title: "2", text: "hai"})

    assert post1 == TestRepo.get(Post, post1.id)
    assert post2 == TestRepo.get(Post, post2.id)
    assert nil == TestRepo.get(Post, -1)
  end

  test "get model with custom primary key" do
    TestRepo.insert(%Custom{foo: "1"})
    TestRepo.insert(%Custom{foo: "2"})

    assert %Custom{foo: "1"} == TestRepo.get(Custom, "1")
    assert %Custom{foo: "2"} == TestRepo.get(Custom, "2")
    assert nil == TestRepo.get(Custom, "3")
  end

  test "one raises when result is more than one row" do
    assert %Post{} = TestRepo.insert(%Post{title: "1", text: "hai"})
    assert %Post{} = TestRepo.insert(%Post{title: "2", text: "hai"})

    assert_raise Ecto.NotSingleResult, fn ->
      TestRepo.one(from p in Post, where: p.text == "hai")
    end

    assert_raise Ecto.NotSingleResult, fn ->
      TestRepo.one!(from p in Post, where: p.text == "hai")
    end
  end

  test "one with bang raises when there are no results" do
    assert nil == TestRepo.one(from p in Post, where: p.text == "hai")

    assert_raise Ecto.NotSingleResult, fn ->
      TestRepo.one!(from p in Post, where: p.text == "hai")
    end
  end

  test "transform row" do
    assert %Post{} = TestRepo.insert(%Post{title: "1", text: "hai"})

    assert ["1"] == TestRepo.all(from p in Post, select: p.title)

    assert [{ "1", "hai" }] ==
           TestRepo.all(from p in Post, select: { p.title, p.text })

    assert [["1", "hai"]] ==
           TestRepo.all(from p in Post, select: [p.title, p.text])
  end

  test "update some entities" do
    assert %Post{id: id1} = TestRepo.insert(%Post{title: "1", text: "hai"})
    assert %Post{id: id2} = TestRepo.insert(%Post{title: "2", text: "hai"})
    assert %Post{id: id3} = TestRepo.insert(%Post{title: "3", text: "hai"})

    query = from(p in Post, where: p.title == "1" or p.title == "2")
    assert 2 = TestRepo.update_all(query, title: "x")
    assert %Post{title: "x"} = TestRepo.get(Post, id1)
    assert %Post{title: "x"} = TestRepo.get(Post, id2)
    assert %Post{title: "3"} = TestRepo.get(Post, id3)
  end

  test "update all entities" do
    assert %Post{id: id1} = TestRepo.insert(%Post{title: "1", text: "hai"})
    assert %Post{id: id2} = TestRepo.insert(%Post{title: "2", text: "hai"})
    assert %Post{id: id3} = TestRepo.insert(%Post{title: "3", text: "hai"})

    assert 3 = TestRepo.update_all(Post, title: "x")
    assert %Post{title: "x"} = TestRepo.get(Post, id1)
    assert %Post{title: "x"} = TestRepo.get(Post, id2)
    assert %Post{title: "x"} = TestRepo.get(Post, id3)
  end

  test "update no entities" do
    assert %Post{id: id1} = TestRepo.insert(%Post{title: "1", text: "hai"})
    assert %Post{id: id2} = TestRepo.insert(%Post{title: "2", text: "hai"})
    assert %Post{id: id3} = TestRepo.insert(%Post{title: "3", text: "hai"})

    query = from(p in Post, where: p.title == "4")
    assert 0 = TestRepo.update_all(query, title: "x")
    assert %Post{title: "1"} = TestRepo.get(Post, id1)
    assert %Post{title: "2"} = TestRepo.get(Post, id2)
    assert %Post{title: "3"} = TestRepo.get(Post, id3)
  end

  test "update expression syntax" do
    assert %Post{id: id1} = TestRepo.insert(%Post{title: "1", text: "hai"})
    assert %Post{id: id2} = TestRepo.insert(%Post{title: "2", text: "hai"})

    assert 2 = TestRepo.update_all(p in Post, text: p.text <> "bai")
    assert %Post{text: "haibai"} = TestRepo.get(Post, id1)
    assert %Post{text: "haibai"} = TestRepo.get(Post, id2)
  end

  test "delete some entities" do
    assert %Post{} = TestRepo.insert(%Post{title: "1", text: "hai"})
    assert %Post{} = TestRepo.insert(%Post{title: "2", text: "hai"})
    assert %Post{} = TestRepo.insert(%Post{title: "3", text: "hai"})

    query = from(p in Post, where: p.title == "1" or p.title == "2")
    assert 2 = TestRepo.delete_all(query)
    assert [%Post{}] = TestRepo.all(Post)
  end

  test "delete all entities" do
    assert %Post{} = TestRepo.insert(%Post{title: "1", text: "hai"})
    assert %Post{} = TestRepo.insert(%Post{title: "2", text: "hai"})
    assert %Post{} = TestRepo.insert(%Post{title: "3", text: "hai"})

    assert 3 = TestRepo.delete_all(from(p in Post, where: p.id > 0))
    assert [] = TestRepo.all(Post)
  end

  test "delete no entities" do
    assert %Post{id: id1} = TestRepo.insert(%Post{title: "1", text: "hai"})
    assert %Post{id: id2} = TestRepo.insert(%Post{title: "2", text: "hai"})
    assert %Post{id: id3} = TestRepo.insert(%Post{title: "3", text: "hai"})

    query = from(p in Post, where: p.title == "4")
    assert 0 = TestRepo.delete_all(query)
    assert %Post{title: "1"} = TestRepo.get(Post, id1)
    assert %Post{title: "2"} = TestRepo.get(Post, id2)
    assert %Post{title: "3"} = TestRepo.get(Post, id3)
  end

  #test "custom functions" do
    #assert %Post{id: id1} = TestRepo.insert(%Post{title: "hi"})
    #assert [id1*10] == TestRepo.all(from p in Post, select: custom(p.id))
  #end

  test "virtual field" do
    assert %Post{id: id} = TestRepo.insert(%Post{title: "1", text: "hai"})
    assert TestRepo.get(Post, id).temp == "temp"
  end

  test "preload empty" do
    assert [] == Preloader.run([], TestRepo, :anything_goes)
  end

  test "preload has_many" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "2"})
    p3 = TestRepo.insert(%Post{title: "3"})

    %Comment{id: cid1} = TestRepo.insert(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert(%Comment{text: "2", post_id: p1.id})
    %Comment{id: cid3} = TestRepo.insert(%Comment{text: "3", post_id: p2.id})
    %Comment{id: cid4} = TestRepo.insert(%Comment{text: "4", post_id: p2.id})

    assert_raise Ecto.AssociationNotLoadedError, fn ->
      p1.comments.all
    end
    assert p1.comments.loaded? == false

    assert [p3, p1, p2] = Preloader.run([p3, p1, p2], TestRepo, :comments)
    assert [%Comment{id: ^cid1}, %Comment{id: ^cid2}] = p1.comments.all
    assert [%Comment{id: ^cid3}, %Comment{id: ^cid4}] = p2.comments.all
    assert [] = p3.comments.all
    assert p1.comments.loaded? == true
  end

  test "preload has_one" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "2"})
    p3 = TestRepo.insert(%Post{title: "3"})

    %Permalink{id: pid1} = TestRepo.insert(%Permalink{url: "1", post_id: p1.id})
    %Permalink{}         = TestRepo.insert(%Permalink{url: "2", post_id: nil})
    %Permalink{id: pid3} = TestRepo.insert(%Permalink{url: "3", post_id: p3.id})

    assert_raise Ecto.AssociationNotLoadedError, fn ->
      p1.permalink.get
    end
    assert_raise Ecto.AssociationNotLoadedError, fn ->
      p2.permalink.get
    end
    assert p1.permalink.loaded? == false

    assert [p3, p1, p2] = Preloader.run([p3, p1, p2], TestRepo, :permalink)
    assert %Permalink{id: ^pid1} = p1.permalink.get
    assert nil = p2.permalink.get
    assert %Permalink{id: ^pid3} = p3.permalink.get
    assert p1.permalink.loaded? == true
  end

  test "preload belongs_to" do
    %Post{id: pid1} = TestRepo.insert(%Post{title: "1"})
    TestRepo.insert(%Post{title: "2"})
    %Post{id: pid3} = TestRepo.insert(%Post{title: "3"})

    pl1 = TestRepo.insert(%Permalink{url: "1", post_id: pid1})
    pl2 = TestRepo.insert(%Permalink{url: "2", post_id: nil})
    pl3 = TestRepo.insert(%Permalink{url: "3", post_id: pid3})

    assert_raise Ecto.AssociationNotLoadedError, fn ->
      pl1.post.get
    end
    assert pl1.post.loaded? == false

    assert [pl3, pl1, pl2] = Preloader.run([pl3, pl1, pl2], TestRepo, :post)
    assert %Post{id: ^pid1} = pl1.post.get
    assert nil = pl2.post.get
    assert %Post{id: ^pid3} = pl3.post.get
    assert pl1.post.loaded? == true
  end

  test "preload belongs_to with shared assocs 1" do
    %Post{id: pid1} = TestRepo.insert(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert(%Post{title: "2"})

    c1 = TestRepo.insert(%Comment{text: "1", post_id: pid1})
    c2 = TestRepo.insert(%Comment{text: "2", post_id: pid1})
    c3 = TestRepo.insert(%Comment{text: "3", post_id: pid2})

    assert [c3, c1, c2] = Preloader.run([c3, c1, c2], TestRepo, :post)
    assert %Post{id: ^pid1} = c1.post.get
    assert %Post{id: ^pid1} = c2.post.get
    assert %Post{id: ^pid2} = c3.post.get
  end

  test "preload belongs_to with shared assocs 2" do
    %Post{id: pid1} = TestRepo.insert(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert(%Post{title: "2"})

    c1 = TestRepo.insert(%Comment{text: "1", post_id: pid1})
    c2 = TestRepo.insert(%Comment{text: "2", post_id: pid2})
    c3 = TestRepo.insert(%Comment{text: "3", post_id: nil})

    assert [c3, c1, c2] = Preloader.run([c3, c1, c2], TestRepo, :post)
    assert %Post{id: ^pid1} = c1.post.get
    assert %Post{id: ^pid2} = c2.post.get
    assert nil = c3.post.get
  end

  test "preload nils" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "2"})

    assert [%Post{}, nil, %Post{}] =
           Preloader.run([p1, nil, p2], TestRepo, :permalink)

    c1 = TestRepo.insert(%Comment{text: "1", post_id: p1.id})
    c2 = TestRepo.insert(%Comment{text: "2", post_id: p2.id})

    assert [%Comment{}, nil, %Comment{}] =
           Preloader.run([c1, nil, c2], TestRepo, :post)
  end

  test "preload nested" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "2"})

    TestRepo.insert(%Comment{text: "1", post_id: p1.id})
    TestRepo.insert(%Comment{text: "2", post_id: p1.id})
    TestRepo.insert(%Comment{text: "3", post_id: p2.id})
    TestRepo.insert(%Comment{text: "4", post_id: p2.id})

    assert [p2, p1] = Preloader.run([p2, p1], TestRepo, [comments: :post])
    assert [c1, c2] = p1.comments.all
    assert [c3, c4] = p2.comments.all
    assert p1.id == c1.post.get.id
    assert p1.id == c2.post.get.id
    assert p2.id == c3.post.get.id
    assert p2.id == c4.post.get.id
  end

  test "preload keyword query" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "2"})
    TestRepo.insert(%Post{title: "3"})

    %Comment{id: cid1} = TestRepo.insert(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert(%Comment{text: "2", post_id: p1.id})
    %Comment{id: cid3} = TestRepo.insert(%Comment{text: "3", post_id: p2.id})
    %Comment{id: cid4} = TestRepo.insert(%Comment{text: "4", post_id: p2.id})

    query = from(p in Post, preload: [:comments], select: p)

    assert [p1, p2, p3] = TestRepo.all(query)
    assert [%Comment{id: ^cid1}, %Comment{id: ^cid2}] = p1.comments.all
    assert [%Comment{id: ^cid3}, %Comment{id: ^cid4}] = p2.comments.all
    assert [] = p3.comments.all

    query = from(p in Post, preload: [:comments], select: { 0, [p] })
    posts = TestRepo.all(query)
    [p1, p2, p3] = Enum.map(posts, fn { 0, [p] } -> p end)

    assert [%Comment{id: ^cid1}, %Comment{id: ^cid2}] = p1.comments.all
    assert [%Comment{id: ^cid3}, %Comment{id: ^cid4}] = p2.comments.all
    assert [] = p3.comments.all
  end

  test "row transform" do
    post = TestRepo.insert(%Post{title: "1", text: "hi"})
    query = from(p in Post, select: { p.title, [ p, { p.text } ] })
    [{ "1", [ ^post, { "hi" } ] }] = TestRepo.all(query)
  end

  test "join" do
    post = TestRepo.insert(%Post{title: "1", text: "hi"})
    comment = TestRepo.insert(%Comment{text: "hey"})
    query = from(p in Post, join: c in Comment, on: true, select: { p, c })
    assert [{ ^post, ^comment }] = TestRepo.all(query)
  end

  test "has_many association join" do
    post = TestRepo.insert(%Post{title: "1", text: "hi"})
    c1 = TestRepo.insert(%Comment{text: "hey", post_id: post.id})
    c2 = TestRepo.insert(%Comment{text: "heya", post_id: post.id})

    query = from(p in Post, join: c in p.comments, select: { p, c })
    [{ ^post, ^c1 }, { ^post, ^c2 }] = TestRepo.all(query)
  end

  test "has_one association join" do
    post = TestRepo.insert(%Post{title: "1", text: "hi"})
    p1 = TestRepo.insert(%Permalink{url: "hey", post_id: post.id})
    p2 = TestRepo.insert(%Permalink{url: "heya", post_id: post.id})

    query = from(p in Post, join: c in p.permalink, select: { p, c })
    [{ ^post, ^p1 }, { ^post, ^p2 }] = TestRepo.all(query)
  end

  test "belongs_to association join" do
    post = TestRepo.insert(%Post{title: "1", text: "hi"})
    p1 = TestRepo.insert(%Permalink{url: "hey", post_id: post.id})
    p2 = TestRepo.insert(%Permalink{url: "heya", post_id: post.id})

    query = from(p in Permalink, join: c in p.post, select: { p, c })
    [{ ^p1, ^post }, { ^p2, ^post }] = TestRepo.all(query)
  end

  test "has_many implements Enum.count protocol correctly" do
    post = TestRepo.insert(%Post{title: "1"})
    TestRepo.insert(%Comment{text: "1", post_id: post.id})

    post1 = TestRepo.all(from p in Post, preload: [:comments]) |> hd

    assert Enum.count(post1.comments.all) == 1
  end

  test "has_many queryable" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "1"})

    %Comment{id: cid1} = TestRepo.insert(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert(%Comment{text: "2", post_id: p1.id})
    %Comment{id: cid3} = TestRepo.insert(%Comment{text: "3", post_id: p2.id})

    assert [%Comment{id: ^cid1}, %Comment{id: ^cid2}] = TestRepo.all(p1.comments)
    assert [%Comment{id: ^cid3}] = TestRepo.all(p2.comments)

    query = from(c in p1.comments, where: c.text == "1")
    assert [%Comment{id: ^cid1}] = TestRepo.all(query)
  end

  test "has_many assoc selector" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "1"})

    %Comment{id: cid1} = TestRepo.insert(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert(%Comment{text: "2", post_id: p1.id})
    %Comment{id: cid3} = TestRepo.insert(%Comment{text: "3", post_id: p2.id})

    query = from(p in Post, join: c in p.comments, select: assoc(p, comments: c))
    assert [post1, post2] = TestRepo.all(query)
    assert [%Comment{id: ^cid1}, %Comment{id: ^cid2}] = post1.comments.all
    assert [%Comment{id: ^cid3}] = post2.comments.all
    assert post1.comments.loaded? == true
  end

  test "has_many assoc selector reversed" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "2"})
         TestRepo.insert(%Post{title: "3"})

    TestRepo.insert(%Comment{text: "1", post_id: p1.id})
    TestRepo.insert(%Comment{text: "2", post_id: p1.id})
    TestRepo.insert(%Comment{text: "3", post_id: p2.id})
    TestRepo.insert(%Comment{text: "4"})

    query = from(p in Post, left_join: c in p.comments, select: assoc(c, post: p))
    res1 = TestRepo.all(query)

    query = from(p in Post, right_join: c in p.comments, select: assoc(c, post: p))
    res2 = TestRepo.all(query)

    query = from(p in Post, join: c in p.comments, select: assoc(c, post: p))
    res3 = TestRepo.all(query)

    assert [c1, c2, c3] = res1
    assert %Comment{text: "1"} = c1
    assert %Comment{text: "2"} = c2
    assert %Comment{text: "3"} = c3
    assert %Post{title: "1"}   = c1.post.get
    assert %Post{title: "1"}   = c2.post.get
    assert %Post{title: "2"}   = c3.post.get

    assert [c1, c2, c3, c4] = res2
    assert %Comment{text: "1"} = c1
    assert %Comment{text: "2"} = c2
    assert %Comment{text: "3"} = c3
    assert %Comment{text: "4"} = c4
    assert %Post{title: "1"}   = c1.post.get
    assert %Post{title: "1"}   = c2.post.get
    assert %Post{title: "2"}   = c3.post.get
    assert nil                 = c4.post.get

    assert res1 == res3
  end

  test "has_one assoc selector" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "2"})

    %Permalink{id: pid1} = TestRepo.insert(%Permalink{url: "1", post_id: p1.id})
    %Permalink{}         = TestRepo.insert(%Permalink{url: "2"})
    %Permalink{id: pid3} = TestRepo.insert(%Permalink{url: "3", post_id: p2.id})

    query = from(p in Post, join: pl in p.permalink, select: assoc(p, permalink: pl))
    assert [post1, post3] = TestRepo.all(query)
    assert %Permalink{id: ^pid1} = post1.permalink.get
    assert %Permalink{id: ^pid3} = post3.permalink.get
    assert post1.permalink.loaded? == true
  end

  test "has_one assoc selector reversed" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "2"})

    TestRepo.insert(%Permalink{url: "1", post_id: p1.id})
    TestRepo.insert(%Permalink{url: "2"})
    TestRepo.insert(%Permalink{url: "3", post_id: p2.id})

    query = from(p in Post, left_join: pl in p.permalink, select: assoc(pl, post: p))
    res1 = TestRepo.all(query)

    query = from(p in Post, right_join: pl in p.permalink, select: assoc(pl, post: p))
    res2 = TestRepo.all(query)

    query = from(p in Post, join: pl in p.permalink, select: assoc(pl, post: p))
    res3 = TestRepo.all(query)

    assert [pl1, pl3] = res1
    assert %Permalink{url: "1"} = pl1
    assert %Permalink{url: "3"} = pl3
    assert %Post{title: "1"}    = pl1.post.get
    assert %Post{title: "2"}    = pl3.post.get

    assert [pl1, pl2, pl3] = res2
    assert %Permalink{url: "1"} = pl1
    assert %Permalink{url: "2"} = pl2
    assert %Permalink{url: "3"} = pl3
    assert %Post{title: "1"}    = pl1.post.get
    assert nil                  = pl2.post.get
    assert %Post{title: "2"}    = pl3.post.get

    assert res1 == res3
  end

  test "belongs_to assoc selector" do
    %Post{id: pid1} = TestRepo.insert(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert(%Post{title: "2"})

    TestRepo.insert(%Permalink{url: "1", post_id: pid1})
    TestRepo.insert(%Permalink{url: "2"})
    TestRepo.insert(%Permalink{url: "3", post_id: pid2})

    query = from(pl in Permalink, left_join: p in pl.post, select: assoc(pl, post: p))
    assert [p1, p2, p3] = TestRepo.all(query)
    assert %Post{id: ^pid1} = p1.post.get
    assert nil = p2.post.get
    assert %Post{id: ^pid2} = p3.post.get
    assert p1.post.loaded?
    assert p2.post.loaded?
  end

  test "belongs_to assoc selector reversed" do
    %Post{id: pid1} = TestRepo.insert(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert(%Post{title: "2"})
    %Post{} = TestRepo.insert(%Post{title: "3"})

    TestRepo.insert(%Permalink{url: "1", post_id: pid1})
    TestRepo.insert(%Permalink{url: "2"})
    TestRepo.insert(%Permalink{url: "3", post_id: pid2})

    query = from(pl in Permalink, left_join: p in pl.post, select: assoc(p, permalink: pl))
    res1 = TestRepo.all(query)

    query = from(pl in Permalink, right_join: p in pl.post, select: assoc(p, permalink: pl))
    res2 = TestRepo.all(query)

    query = from(pl in Permalink, join: p in pl.post, select: assoc(p, permalink: pl))
    res3 = TestRepo.all(query)

    assert [p1, p2] = res1
    assert %Post{title: "1"}    = p1
    assert %Post{title: "2"}    = p2
    assert %Permalink{url: "1"} = p1.permalink.get
    assert %Permalink{url: "3"} = p2.permalink.get

    assert [p1, p2, p3] = res2
    assert %Post{title: "1"}    = p1
    assert %Post{title: "2"}    = p2
    assert %Post{title: "3"}    = p3
    assert %Permalink{url: "1"} = p1.permalink.get
    assert %Permalink{url: "3"} = p2.permalink.get
    assert nil                  = p3.permalink.get

    assert res1 == res3
  end

  test "belongs_to assoc selector with shared assoc" do
    %Post{id: pid1} = TestRepo.insert(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert(%Post{title: "2"})

    c1 = TestRepo.insert(%Comment{text: "1", post_id: pid1})
    c2 = TestRepo.insert(%Comment{text: "2", post_id: pid1})
    c3 = TestRepo.insert(%Comment{text: "3", post_id: pid2})

    query = from(c in Comment, join: p in c.post, select: assoc(c, post: p))
    assert [c1, c2, c3] = TestRepo.all(query)
    assert %Post{id: ^pid1} = c1.post.get
    assert %Post{id: ^pid1} = c2.post.get
    assert %Post{id: ^pid2} = c3.post.get
  end

  test "belongs_to assoc selector with shared assoc 2" do
    %Post{id: pid1} = TestRepo.insert(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert(%Post{title: "2"})

    c1 = TestRepo.insert(%Comment{text: "1", post_id: pid1})
    c2 = TestRepo.insert(%Comment{text: "2", post_id: pid2})
    c3 = TestRepo.insert(%Comment{text: "3", post_id: nil})

    query = from(c in Comment, left_join: p in c.post, select: assoc(c, post: p))
    assert [c1, c2, c3] = TestRepo.all(query)
    assert %Post{id: ^pid1} = c1.post.get
    assert %Post{id: ^pid2} = c2.post.get
    assert nil = c3.post.get
  end

  test "nested assoc" do
    %Post{id: pid1} = TestRepo.insert(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert(%Post{title: "2"})

    %User{id: uid1} = TestRepo.insert(%User{name: "1"})
    %User{id: uid2} = TestRepo.insert(%User{name: "2"})

    %Comment{id: cid1} = TestRepo.insert(%Comment{text: "1", post_id: pid1, author_id: uid1})
    %Comment{id: cid2} = TestRepo.insert(%Comment{text: "2", post_id: pid1, author_id: uid2})
    %Comment{id: cid3} = TestRepo.insert(%Comment{text: "3", post_id: pid2, author_id: uid2})

    query = from p in Post,
      left_join: c in p.comments,
      left_join: u in c.author,
      order_by: [p.id, c.id, u.id],
      select: assoc(p, comments: assoc(c, author: u))

    assert [p1, p2] = TestRepo.all(query)
    assert p1.id == pid1
    assert p2.id == pid2

    assert [c1, c2] = p1.comments.all
    assert [c3] = p2.comments.all
    assert c1.id == cid1
    assert c2.id == cid2
    assert c3.id == cid3

    assert c1.author.get.id == uid1
    assert c2.author.get.id == uid2
    assert c3.author.get.id == uid2
  end

  test "nested assoc with missing records" do
    %Post{id: pid1} = TestRepo.insert(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert(%Post{title: "2"})
    %Post{id: pid3} = TestRepo.insert(%Post{title: "2"})

    %User{id: uid1} = TestRepo.insert(%User{name: "1"})
    %User{id: uid2} = TestRepo.insert(%User{name: "2"})

    %Comment{id: cid1} = TestRepo.insert(%Comment{text: "1", post_id: pid1, author_id: uid1})
    %Comment{id: cid2} = TestRepo.insert(%Comment{text: "2", post_id: pid1, author_id: nil})
    %Comment{id: cid3} = TestRepo.insert(%Comment{text: "3", post_id: pid3, author_id: uid2})

    query = from p in Post,
      left_join: c in p.comments,
      left_join: u in c.author,
      order_by: [p.id, c.id, u.id],
      select: assoc(p, comments: assoc(c, author: u))

    assert [p1, p2, p3] = TestRepo.all(query)
    assert p1.id == pid1
    assert p2.id == pid2
    assert p3.id == pid3

    assert [c1, c2] = p1.comments.all
    assert [] = p2.comments.all
    assert [c3] = p3.comments.all
    assert c1.id == cid1
    assert c2.id == cid2
    assert c3.id == cid3

    assert c1.author.get.id == uid1
    assert c2.author.get == nil
    assert c3.author.get.id == uid2
  end

  test "join qualifier" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "2"})
    c1 = TestRepo.insert(%Permalink{url: "1", post_id: p2.id})

    query = from(p in Post, left_join: c in p.permalink, order_by: p.id, select: {p, c})
    assert [{^p1, nil}, {^p2, ^c1}] = TestRepo.all(query)
  end
end
