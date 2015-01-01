defmodule Ecto.Integration.RepoTest do
  use Ecto.Integration.Postgres.Case

  test "returns already started for started repos" do
    assert {:error, {:already_started, _}} = TestRepo.start_link
  end

  test "types" do
    TestRepo.insert(%Post{})
    TestRepo.insert(%Comment{})

    # Booleans
    assert [{true, false}] = TestRepo.all(from Post, select: {true, false})

    # nil
    assert [nil] = TestRepo.all(from Post, select: nil)

    # Numbers
    assert [{1, 1.0}] = TestRepo.all(from Post, select: {1, 1.0})

    # Binaries
    assert [_] = TestRepo.all(from p in Post, where: p.bin == ^<<0, 1>> or true)
    assert [_] = TestRepo.all(from p in Post, where: p.bin == <<0, 1>> or true)

    # UUID
    uuid = <<0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15>>
    assert [_] = TestRepo.all(from p in Post, where: p.uuid == ^uuid or true)
    assert [_] = TestRepo.all(from p in Post, where: p.uuid == uuid(<<0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15>>) or true)

    # Datetime
    datetime = %Ecto.DateTime{year: 2014, month: 1, day: 16, hour: 20, min: 26, sec: 51}
    assert [_] = TestRepo.all(from c in Comment, where: c.posted == ^datetime or true)

    # Lists
    assert [[1, 2, 3]] = TestRepo.all(from Post, select: [1, 2, 3])
    assert [_] = TestRepo.all(from p in Post, where: p.tags == ["foo", "bar"] or true)
    assert [_] = TestRepo.all(from p in Post, where: p.tags == ^["foo", "bar"] or true)
    assert [_] = TestRepo.all(from p in Post, where: p.tags == ^[] or true)
  end

  test "fetch empty" do
    assert [] == TestRepo.all(Post)
    assert [] == TestRepo.all(from p in Post)
  end

  test "fetch without model" do
    %Post{id: id} = TestRepo.insert(%Post{title: "title1"})
    %Post{} = TestRepo.insert(%Post{title: "title2"})

    assert ["title1", "title2"] =
      TestRepo.all(from(p in "posts", order_by: p.title, select: p.title))

    assert [^id] =
      TestRepo.all(from(p in "posts", where: p.title == "title1", select: p.id))
  end

  test "insert, update and delete" do
    post = %Post{title: "create and delete single", text: "fetch empty"}

    assert %Post{} = TestRepo.insert(post)
    assert %Post{} = created = TestRepo.insert(post)
    assert %Post{} = TestRepo.delete(created)

    assert [%Post{}] = TestRepo.all(Post)

    post = TestRepo.one(Post)
    post = %{post | text: "coming very soon..."}
    assert %Post{} = TestRepo.update(post)
  end

  test "insert and update binary inferred type values" do
    bin   = <<1>>
    uuid  = <<0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15>>
    array = ["foo", "bar"]

    post = %Post{bin: bin, uuid: uuid, tags: array}
    post = TestRepo.insert(post)
    assert %Post{bin: ^bin, uuid: ^uuid, tags: ^array} = post

    assert %Post{} = TestRepo.update(post)
    assert [%Post{bin: ^bin, uuid: ^uuid, tags: ^array}] = TestRepo.all(Post)
  end

  test "insert and update datetime inferred type values" do
    date = %Ecto.Date{year: 2014, month: 12, day: 24}
    time = %Ecto.Time{hour: 18, min: 41, sec: 24}
    datetime = %Ecto.DateTime{year: 2014, month: 12, day: 24, hour: 18, min: 41, sec: 24}

    comment = %Comment{day: date, time: time, posted: datetime}
    comment = TestRepo.insert(comment)
    assert %Comment{day: ^date, time: ^time, posted: ^datetime} = comment

    assert %Comment{} = TestRepo.update(comment)
    assert [%Comment{day: ^date, time: ^time, posted: ^datetime}] = TestRepo.all(Comment)
  end

  test "insert with no primary key" do
    assert %Barebone{text: nil} = TestRepo.insert(%Barebone{})
    assert %Barebone{text: "text"} = TestRepo.insert(%Barebone{text: "text"})
  end

  test "insert with user-assigned primary key" do
    assert %Post{id: 1} = TestRepo.insert(%Post{id: 1})
  end

  test "get(!)" do
    post1 = TestRepo.insert(%Post{title: "1", text: "hai"})
    post2 = TestRepo.insert(%Post{title: "2", text: "hai"})

    assert post1 == TestRepo.get(Post, post1.id)
    assert post2 == TestRepo.get(Post, to_string post2.id) # With casting
    assert nil   == TestRepo.get(Post, -1)

    assert post1 == TestRepo.get!(Post, post1.id)
    assert post2 == TestRepo.get!(Post, to_string post2.id) # With casting

    assert_raise Ecto.NoResultsError, fn ->
      TestRepo.get!(Post, -1)
    end
  end

  test "get(!) with custom primary key" do
    TestRepo.insert(%Custom{foo: "01abcdef01abcdef"})
    TestRepo.insert(%Custom{foo: "02abcdef02abcdef"})

    assert %Custom{foo: "01abcdef01abcdef"} == TestRepo.get(Custom, "01abcdef01abcdef")
    assert %Custom{foo: "02abcdef02abcdef"} == TestRepo.get(Custom, "02abcdef02abcdef")
    assert nil == TestRepo.get(Custom, "03abcdef03abcdef")
  end

  test "one(!)" do
    post1 = TestRepo.insert(%Post{title: "1", text: "hai"})
    post2 = TestRepo.insert(%Post{title: "2", text: "hai"})

    assert post1 == TestRepo.one(from p in Post, where: p.id == ^post1.id)
    assert post2 == TestRepo.one(from p in Post, where: p.id == ^to_string post2.id) # With casting
    assert nil   == TestRepo.one(from p in Post, where: p.id == ^-1)

    assert post1 == TestRepo.one!(from p in Post, where: p.id == ^post1.id)
    assert post2 == TestRepo.one!(from p in Post, where: p.id == ^to_string post2.id) # With casting

    assert_raise Ecto.NoResultsError, fn ->
      TestRepo.one!(from p in Post, where: p.id == ^-1)
    end
  end

  test "one(!) with multiple results" do
    assert %Post{} = TestRepo.insert(%Post{title: "1", text: "hai"})
    assert %Post{} = TestRepo.insert(%Post{title: "2", text: "hai"})

    assert_raise Ecto.MultipleResultsError, fn ->
      TestRepo.one(from p in Post, where: p.text == "hai")
    end

    assert_raise Ecto.MultipleResultsError, fn ->
      TestRepo.one!(from p in Post, where: p.text == "hai")
    end
  end

  test "data structures in select" do
    assert %Post{} = TestRepo.insert(%Post{title: "1", text: "hai"})

    assert ["1"] == TestRepo.all(from p in Post, select: p.title)

    assert [{"1", "hai"}] ==
           TestRepo.all(from p in Post, select: {p.title, p.text})

    assert [["1", "hai"]] ==
           TestRepo.all(from p in Post, select: [p.title, p.text])
  end

  test "update all" do
    assert %Post{id: id1} = TestRepo.insert(%Post{title: "1"})
    assert %Post{id: id2} = TestRepo.insert(%Post{title: "2"})
    assert %Post{id: id3} = TestRepo.insert(%Post{title: "3"})

    assert 3 = TestRepo.update_all(Post, title: "x")

    assert %Post{title: "x"} = TestRepo.get(Post, id1)
    assert %Post{title: "x"} = TestRepo.get(Post, id2)
    assert %Post{title: "x"} = TestRepo.get(Post, id3)

    assert 3 = TestRepo.update_all("posts", title: "y")

    assert %Post{title: "y"} = TestRepo.get(Post, id1)
    assert %Post{title: "y"} = TestRepo.get(Post, id2)
    assert %Post{title: "y"} = TestRepo.get(Post, id3)
  end

  test "update all with filter" do
    assert %Post{id: id1} = TestRepo.insert(%Post{title: "1"})
    assert %Post{id: id2} = TestRepo.insert(%Post{title: "2"})
    assert %Post{id: id3} = TestRepo.insert(%Post{title: "3"})

    query = from(p in Post, where: p.title == "1" or p.title == "2")
    assert 2 = TestRepo.update_all(query, title: "x", text: "")

    assert %Post{title: "x"} = TestRepo.get(Post, id1)
    assert %Post{title: "x"} = TestRepo.get(Post, id2)
    assert %Post{title: "3"} = TestRepo.get(Post, id3)
  end

  test "update all no entries" do
    assert %Post{id: id1} = TestRepo.insert(%Post{title: "1"})
    assert %Post{id: id2} = TestRepo.insert(%Post{title: "2"})
    assert %Post{id: id3} = TestRepo.insert(%Post{title: "3"})

    query = from(p in Post, where: p.title == "4")
    assert 0 = TestRepo.update_all(query, title: "x")

    assert %Post{title: "1"} = TestRepo.get(Post, id1)
    assert %Post{title: "2"} = TestRepo.get(Post, id2)
    assert %Post{title: "3"} = TestRepo.get(Post, id3)
  end

  test "update all expression syntax" do
    assert %Post{id: id1} = TestRepo.insert(%Post{title: "1", text: "hai"})
    assert %Post{id: id2} = TestRepo.insert(%Post{title: "2", text: "hai"})

    # Expressions
    query = from p in Post, where: p.id > 0
    assert 2 = TestRepo.update_all(p in query, text: fragment("? || 'bai'", p.text))

    assert %Post{text: "haibai"} = TestRepo.get(Post, id1)
    assert %Post{text: "haibai"} = TestRepo.get(Post, id2)

    # Nil values
    assert 2 = TestRepo.update_all(p in Post, text: nil)

    assert %Post{text: nil} = TestRepo.get(Post, id1)
    assert %Post{text: nil} = TestRepo.get(Post, id2)

    # Interpolated values with casting
    text = "hai"
    assert 2 = TestRepo.update_all(p in Post, text: ^text, counter: ^to_string(id1))

    assert %Post{text: "hai", counter: ^id1} = TestRepo.get(Post, id1)
    assert %Post{text: "hai", counter: ^id1} = TestRepo.get(Post, id2)
  end

  test "delete all" do
    assert %Post{} = TestRepo.insert(%Post{title: "1", text: "hai"})
    assert %Post{} = TestRepo.insert(%Post{title: "2", text: "hai"})
    assert %Post{} = TestRepo.insert(%Post{title: "3", text: "hai"})

    assert 3 = TestRepo.delete_all(Post)
    assert [] = TestRepo.all(Post)
  end

  test "delete all with filter" do
    assert %Post{} = TestRepo.insert(%Post{title: "1", text: "hai"})
    assert %Post{} = TestRepo.insert(%Post{title: "2", text: "hai"})
    assert %Post{} = TestRepo.insert(%Post{title: "3", text: "hai"})

    query = from(p in Post, where: p.title == "1" or p.title == "2")
    assert 2 = TestRepo.delete_all(query)
    assert [%Post{}] = TestRepo.all(Post)
  end

  test "delete all no entries" do
    assert %Post{id: id1} = TestRepo.insert(%Post{title: "1", text: "hai"})
    assert %Post{id: id2} = TestRepo.insert(%Post{title: "2", text: "hai"})
    assert %Post{id: id3} = TestRepo.insert(%Post{title: "3", text: "hai"})

    query = from(p in Post, where: p.title == "4")
    assert 0 = TestRepo.delete_all(query)
    assert %Post{title: "1"} = TestRepo.get(Post, id1)
    assert %Post{title: "2"} = TestRepo.get(Post, id2)
    assert %Post{title: "3"} = TestRepo.get(Post, id3)
  end

  test "virtual field" do
    assert %Post{id: id} = TestRepo.insert(%Post{title: "1", text: "hai"})
    assert TestRepo.get(Post, id).temp == "temp"
  end

  ## Joins

  test "joins" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "2"})
    c1 = TestRepo.insert(%Permalink{url: "1", post_id: p2.id})

    query = from(p in Post, join: c in assoc(p, :permalink), order_by: p.id, select: {p, c})
    assert [{^p2, ^c1}] = TestRepo.all(query)

    query = from(p in Post, left_join: c in assoc(p, :permalink), order_by: p.id, select: {p, c})
    assert [{^p1, nil}, {^p2, ^c1}] = TestRepo.all(query)
  end

  test "has_many association join" do
    post = TestRepo.insert(%Post{title: "1", text: "hi"})
    c1 = TestRepo.insert(%Comment{text: "hey", post_id: post.id})
    c2 = TestRepo.insert(%Comment{text: "heya", post_id: post.id})

    query = from(p in Post, join: c in assoc(p, :comments), select: {p, c})
    [{^post, ^c1}, {^post, ^c2}] = TestRepo.all(query)
  end

  test "has_one association join" do
    post = TestRepo.insert(%Post{title: "1", text: "hi"})
    p1 = TestRepo.insert(%Permalink{url: "hey", post_id: post.id})
    p2 = TestRepo.insert(%Permalink{url: "heya", post_id: post.id})

    query = from(p in Post, join: c in assoc(p, :permalink), select: {p, c})
    [{^post, ^p1}, {^post, ^p2}] = TestRepo.all(query)
  end

  test "belongs_to association join" do
    post = TestRepo.insert(%Post{title: "1", text: "hi"})
    p1 = TestRepo.insert(%Permalink{url: "hey", post_id: post.id})
    p2 = TestRepo.insert(%Permalink{url: "heya", post_id: post.id})

    query = from(p in Permalink, join: c in assoc(p, :post), select: {p, c})
    [{^p1, ^post}, {^p2, ^post}] = TestRepo.all(query)
  end

  ## Preloads

  test "preload empty" do
    assert TestRepo.preload([], :anything_goes) == []
  end

  test "preload has_many" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "2"})
    p3 = TestRepo.insert(%Post{title: "3"})

    %Comment{id: cid1} = TestRepo.insert(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert(%Comment{text: "2", post_id: p1.id})
    %Comment{id: cid3} = TestRepo.insert(%Comment{text: "3", post_id: p2.id})
    %Comment{id: cid4} = TestRepo.insert(%Comment{text: "4", post_id: p2.id})

    assert %Ecto.Associations.NotLoaded{} = p1.comments

    assert [p3, p1, p2] = TestRepo.preload([p3, p1, p2], :comments)
    assert [%Comment{id: ^cid1}, %Comment{id: ^cid2}] = p1.comments
    assert [%Comment{id: ^cid3}, %Comment{id: ^cid4}] = p2.comments
    assert [] = p3.comments
  end

  test "preload has_one" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "2"})
    p3 = TestRepo.insert(%Post{title: "3"})

    %Permalink{id: pid1} = TestRepo.insert(%Permalink{url: "1", post_id: p1.id})
    %Permalink{}         = TestRepo.insert(%Permalink{url: "2", post_id: nil})
    %Permalink{id: pid3} = TestRepo.insert(%Permalink{url: "3", post_id: p3.id})

    assert %Ecto.Associations.NotLoaded{} = p1.permalink
    assert %Ecto.Associations.NotLoaded{} = p2.permalink

    assert [p3, p1, p2] = TestRepo.preload([p3, p1, p2], :permalink)
    assert %Permalink{id: ^pid1} = p1.permalink
    assert nil = p2.permalink
    assert %Permalink{id: ^pid3} = p3.permalink
  end

  test "preload belongs_to" do
    %Post{id: pid1} = TestRepo.insert(%Post{title: "1"})
    TestRepo.insert(%Post{title: "2"})
    %Post{id: pid3} = TestRepo.insert(%Post{title: "3"})

    pl1 = TestRepo.insert(%Permalink{url: "1", post_id: pid1})
    pl2 = TestRepo.insert(%Permalink{url: "2", post_id: nil})
    pl3 = TestRepo.insert(%Permalink{url: "3", post_id: pid3})

    assert %Ecto.Associations.NotLoaded{} = pl1.post

    assert [pl3, pl1, pl2] = TestRepo.preload([pl3, pl1, pl2], :post)
    assert %Post{id: ^pid1} = pl1.post
    assert nil = pl2.post
    assert %Post{id: ^pid3} = pl3.post
  end

  test "preload belongs_to with shared assocs" do
    %Post{id: pid1} = TestRepo.insert(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert(%Post{title: "2"})

    c1 = TestRepo.insert(%Comment{text: "1", post_id: pid1})
    c2 = TestRepo.insert(%Comment{text: "2", post_id: pid1})
    c3 = TestRepo.insert(%Comment{text: "3", post_id: pid2})

    assert [c3, c1, c2] = TestRepo.preload([c3, c1, c2], :post)
    assert %Post{id: ^pid1} = c1.post
    assert %Post{id: ^pid1} = c2.post
    assert %Post{id: ^pid2} = c3.post
  end

  test "preload nested" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "2"})

    TestRepo.insert(%Comment{text: "1", post_id: p1.id})
    TestRepo.insert(%Comment{text: "2", post_id: p1.id})
    TestRepo.insert(%Comment{text: "3", post_id: p2.id})
    TestRepo.insert(%Comment{text: "4", post_id: p2.id})

    assert [p2, p1] = TestRepo.preload([p2, p1], [comments: :post])
    assert [c1, c2] = p1.comments
    assert [c3, c4] = p2.comments
    assert p1.id == c1.post.id
    assert p1.id == c2.post.id
    assert p2.id == c3.post.id
    assert p2.id == c4.post.id
  end

  test "preload has_many with no associated entries" do
    p = TestRepo.insert(%Post{title: "1"})
    p = TestRepo.preload(p, :comments)

    assert p.title == "1"
    assert p.comments == []
  end

  test "preload has_one with no associated entries" do
    p = TestRepo.insert(%Post{title: "1"})
    p = TestRepo.preload(p, :permalink)

    assert p.title == "1"
    assert p.permalink == nil
  end

  test "preload belongs_to with no associated entry" do
    c = TestRepo.insert(%Comment{text: "1"})
    c = TestRepo.preload(c, :post)

    assert c.text == "1"
    assert c.post == nil
  end

  test "preload keyword query" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "2"})
    TestRepo.insert(%Post{title: "3"})

    %Comment{id: cid1} = TestRepo.insert(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert(%Comment{text: "2", post_id: p1.id})
    %Comment{id: cid3} = TestRepo.insert(%Comment{text: "3", post_id: p2.id})
    %Comment{id: cid4} = TestRepo.insert(%Comment{text: "4", post_id: p2.id})

    # Regular query
    query = from(p in Post, preload: [:comments], select: p)

    assert [p1, p2, p3] = TestRepo.all(query)
    assert [%Comment{id: ^cid1}, %Comment{id: ^cid2}] = p1.comments
    assert [%Comment{id: ^cid3}, %Comment{id: ^cid4}] = p2.comments
    assert [] = p3.comments

    # Now let's use an interpolated preload too
    comments = [:comments]
    query = from(p in Post, preload: ^comments, select: {0, [p], 1, 2})

    posts = TestRepo.all(query)
    [p1, p2, p3] = Enum.map(posts, fn {0, [p], 1, 2} -> p end)

    assert [%Comment{id: ^cid1}, %Comment{id: ^cid2}] = p1.comments
    assert [%Comment{id: ^cid3}, %Comment{id: ^cid4}] = p2.comments
    assert [] = p3.comments
  end

  test "preload keyword query with missing entries" do
    %Post{id: pid1} = TestRepo.insert(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert(%Post{title: "2"})

    %Permalink{id: plid1} = TestRepo.insert(%Permalink{url: "1", post_id: pid2})

    %Comment{id: _} = TestRepo.insert(%Comment{text: "1", post_id: pid1})
    %Comment{id: _} = TestRepo.insert(%Comment{text: "2", post_id: pid2})
    %Comment{id: _} = TestRepo.insert(%Comment{text: "3", post_id: nil})

    query = from(p in Post, right_join: c in assoc(p, :comments), preload: :permalink)
    assert [p1, p2, nil] = TestRepo.all(query)
    assert p1.id == pid1
    assert p2.id == pid2

    assert p1.permalink == nil
    assert p2.permalink.id == plid1
  end

  ## Preload assocs

  test "has_many assoc selector" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "1"})

    %Comment{id: cid1} = TestRepo.insert(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert(%Comment{text: "2", post_id: p1.id})
    %Comment{id: cid3} = TestRepo.insert(%Comment{text: "3", post_id: p2.id})

    query = from(p in Post, join: c in assoc(p, :comments), preload: [comments: c])
    assert [post1, post2] = TestRepo.all(query)
    assert [%Comment{id: ^cid1}, %Comment{id: ^cid2}] = post1.comments
    assert [%Comment{id: ^cid3}] = post2.comments
  end

  test "has_one assoc selector" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "2"})

    %Permalink{id: pid1} = TestRepo.insert(%Permalink{url: "1", post_id: p1.id})
    %Permalink{}         = TestRepo.insert(%Permalink{url: "2"})
    %Permalink{id: pid3} = TestRepo.insert(%Permalink{url: "3", post_id: p2.id})

    query = from(p in Post, join: pl in assoc(p, :permalink), preload: [permalink: pl])
    assert [post1, post3] = TestRepo.all(query)

    assert %Permalink{id: ^pid1} = post1.permalink
    assert %Permalink{id: ^pid3} = post3.permalink
  end

  test "belongs_to assoc selector" do
    %Post{id: pid1} = TestRepo.insert(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert(%Post{title: "2"})

    TestRepo.insert(%Permalink{url: "1", post_id: pid1})
    TestRepo.insert(%Permalink{url: "2"})
    TestRepo.insert(%Permalink{url: "3", post_id: pid2})

    query = from(pl in Permalink, left_join: p in assoc(pl, :post), preload: [post: p])
    assert [p1, p2, p3] = TestRepo.all(query)

    assert %Post{id: ^pid1} = p1.post
    assert nil = p2.post
    assert %Post{id: ^pid2} = p3.post
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
      left_join: c in assoc(p, :comments),
      left_join: u in assoc(c, :author),
      order_by: [p.id, c.id, u.id],
      preload: [comments: {c, author: u}],
      select: {0, [p], 1, 2}

    posts = TestRepo.all(query)
    assert [p1, p2] = Enum.map(posts, fn {0, [p], 1, 2} -> p end)
    assert p1.id == pid1
    assert p2.id == pid2

    assert [c1, c2] = p1.comments
    assert [c3] = p2.comments
    assert c1.id == cid1
    assert c2.id == cid2
    assert c3.id == cid3

    assert c1.author.id == uid1
    assert c2.author.id == uid2
    assert c3.author.id == uid2
  end

  test "nested assoc with missing entries" do
    %Post{id: pid1} = TestRepo.insert(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert(%Post{title: "2"})
    %Post{id: pid3} = TestRepo.insert(%Post{title: "2"})

    %User{id: uid1} = TestRepo.insert(%User{name: "1"})
    %User{id: uid2} = TestRepo.insert(%User{name: "2"})

    %Comment{id: cid1} = TestRepo.insert(%Comment{text: "1", post_id: pid1, author_id: uid1})
    %Comment{id: cid2} = TestRepo.insert(%Comment{text: "2", post_id: pid1, author_id: nil})
    %Comment{id: cid3} = TestRepo.insert(%Comment{text: "3", post_id: pid3, author_id: uid2})

    query = from p in Post,
      left_join: c in assoc(p, :comments),
      left_join: u in assoc(c, :author),
      order_by: [p.id, c.id, u.id],
      preload: [comments: {c, author: u}]

    assert [p1, p2, p3] = TestRepo.all(query)
    assert p1.id == pid1
    assert p2.id == pid2
    assert p3.id == pid3

    assert [c1, c2] = p1.comments
    assert [] = p2.comments
    assert [c3] = p3.comments
    assert c1.id == cid1
    assert c2.id == cid2
    assert c3.id == cid3

    assert c1.author.id == uid1
    assert c2.author == nil
    assert c3.author.id == uid2
  end

  test "assoc with preload" do
    %Post{id: pid1} = TestRepo.insert(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert(%Post{title: "2"})

    %Permalink{id: plid1} = TestRepo.insert(%Permalink{url: "1", post_id: pid2})

    %Comment{id: cid1} = TestRepo.insert(%Comment{text: "1", post_id: pid1})
    %Comment{id: cid2} = TestRepo.insert(%Comment{text: "2", post_id: pid2})
    %Comment{id: _}    = TestRepo.insert(%Comment{text: "3", post_id: pid2})

    query = from p in Post,
      left_join: c in assoc(p, :comments),
      where: c.text in ~w(1 2),
      preload: [:permalink, comments: c],
      select: {0, [p], 1, 2}

    posts = TestRepo.all(query)
    assert [p1, p2] = Enum.map(posts, fn {0, [p], 1, 2} -> p end)
    assert p1.id == pid1
    assert p2.id == pid2

    assert p2.permalink.id == plid1

    assert [c1] = p1.comments
    assert [c2] = p2.comments
    assert c1.id == cid1
    assert c2.id == cid2
  end
end
