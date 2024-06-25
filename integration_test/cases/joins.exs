defmodule Ecto.Integration.JoinsTest do
  use Ecto.Integration.Case, async: Application.compile_env(:ecto, :async_integration_tests, true)

  alias Ecto.Integration.TestRepo
  import Ecto.Query

  alias Ecto.Integration.Post
  alias Ecto.Integration.Comment
  alias Ecto.Integration.Permalink
  alias Ecto.Integration.User
  alias Ecto.Integration.PostUserCompositePk

  @tag :update_with_join
  test "update all with joins" do
    user = TestRepo.insert!(%User{name: "Tester"})
    post = TestRepo.insert!(%Post{title: "foo"})
    comment = TestRepo.insert!(%Comment{text: "hey", author_id: user.id, post_id: post.id})

    another_post = TestRepo.insert!(%Post{title: "bar"})
    another_comment = TestRepo.insert!(%Comment{text: "another", author_id: user.id, post_id: another_post.id})

    query = from(c in Comment, join: u in User, on: u.id == c.author_id,
                               where: c.post_id in ^[post.id])

    assert {1, nil} = TestRepo.update_all(query, set: [text: "hoo"])
    assert %Comment{text: "hoo"} = TestRepo.get(Comment, comment.id)
    assert %Comment{text: "another"} = TestRepo.get(Comment, another_comment.id)
  end

  @tag :delete_with_join
  test "delete all with joins" do
    user = TestRepo.insert!(%User{name: "Tester"})
    post = TestRepo.insert!(%Post{title: "foo"})
    TestRepo.insert!(%Comment{text: "hey", author_id: user.id, post_id: post.id})
    TestRepo.insert!(%Comment{text: "foo", author_id: user.id, post_id: post.id})
    TestRepo.insert!(%Comment{text: "bar", author_id: user.id})

    query = from(c in Comment, join: u in User, on: u.id == c.author_id,
                               where: is_nil(c.post_id))
    assert {1, nil} = TestRepo.delete_all(query)
    assert [%Comment{}, %Comment{}] = TestRepo.all(Comment)

    query = from(c in Comment, join: u in assoc(c, :author),
                               join: p in assoc(c, :post),
                               where: p.id in ^[post.id])
    assert {2, nil} = TestRepo.delete_all(query)
    assert [] = TestRepo.all(Comment)
  end

  test "joins" do
    _p = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    c1 = TestRepo.insert!(%Permalink{url: "1", post_id: p2.id})

    query = from(p in Post, join: c in assoc(p, :permalink), order_by: p.id, select: {p, c})
    assert [{^p2, ^c1}] = TestRepo.all(query)

    query = from(p in Post, join: c in assoc(p, :permalink), on: c.id == ^c1.id, select: {p, c})
    assert [{^p2, ^c1}] = TestRepo.all(query)
  end

  test "joins with queries" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    c1 = TestRepo.insert!(%Permalink{url: "1", post_id: p2.id})

    # Joined query without parameter
    permalink = from c in Permalink, where: c.url == "1"

    query = from(p in Post, join: c in ^permalink, on: c.post_id == p.id, select: {p, c})
    assert [{^p2, ^c1}] = TestRepo.all(query)

    # Joined query with parameter
    permalink = from c in Permalink, where: c.url == "1"

    query = from(p in Post, join: c in ^permalink, on: c.id == ^c1.id, order_by: p.title, select: {p, c})
    assert [{^p1, ^c1}, {^p2, ^c1}] = TestRepo.all(query)
  end

  test "named joins" do
    _p = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    c1 = TestRepo.insert!(%Permalink{url: "1", post_id: p2.id})

    query =
      from(p in Post, join: c in assoc(p, :permalink), as: :permalink, order_by: p.id)
      |> select([p, permalink: c], {p, c})

    assert [{^p2, ^c1}] = TestRepo.all(query)
  end

  test "joins with dynamic in :on" do
    p = TestRepo.insert!(%Post{title: "1"})
    c = TestRepo.insert!(%Permalink{url: "1", post_id: p.id})

    join_on = dynamic([p, ..., c], c.id == ^c.id)

    query =
      from(p in Post, join: c in Permalink, on: ^join_on)
      |> select([p, c], {p, c})

    assert [{^p, ^c}] = TestRepo.all(query)

    join_on = dynamic([p, permalink: c], c.id == ^c.id)

    query =
      from(p in Post, join: c in Permalink, as: :permalink, on: ^join_on)
      |> select([p, c], {p, c})

    assert [{^p, ^c}] = TestRepo.all(query)
  end

  @tag :cross_join
  test "cross joins with missing entries" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    c1 = TestRepo.insert!(%Permalink{url: "1", post_id: p2.id})

    query = from(p in Post, cross_join: c in Permalink, order_by: p.id, select: {p, c})
    assert [{^p1, ^c1}, {^p2, ^c1}] = TestRepo.all(query)
  end

  @tag :left_join
  test "left joins with missing entries" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    c1 = TestRepo.insert!(%Permalink{url: "1", post_id: p2.id})

    query = from(p in Post, left_join: c in assoc(p, :permalink), order_by: p.id, select: {p, c})
    assert [{^p1, nil}, {^p2, ^c1}] = TestRepo.all(query)
  end

  @tag :left_join
  test "left join with missing entries from subquery" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    c1 = TestRepo.insert!(%Permalink{url: "1", post_id: p2.id})

    query = from(p in Post, left_join: c in subquery(Permalink), on: p.id == c.post_id, order_by: p.id, select: {p, c})
    assert [{^p1, nil}, {^p2, ^c1}] = TestRepo.all(query)
  end

  @tag :right_join
  test "right joins with missing entries" do
    %Post{id: pid1} = TestRepo.insert!(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert!(%Post{title: "2"})

    %Permalink{id: plid1} = TestRepo.insert!(%Permalink{url: "1", post_id: pid2})

    TestRepo.insert!(%Comment{text: "1", post_id: pid1})
    TestRepo.insert!(%Comment{text: "2", post_id: pid2})
    TestRepo.insert!(%Comment{text: "3", post_id: nil})

    query = from(p in Post, right_join: c in assoc(p, :comments),
                 preload: :permalink, order_by: c.id)
    assert [p1, p2, p3] = TestRepo.all(query)
    assert p1.id == pid1
    assert p2.id == pid2
    assert is_nil(p3.id)

    assert p1.permalink == nil
    assert p2.permalink.id == plid1
  end

  ## Associations joins

  test "has_many association join" do
    post = TestRepo.insert!(%Post{title: "1"})
    c1 = TestRepo.insert!(%Comment{text: "hey", post_id: post.id})
    c2 = TestRepo.insert!(%Comment{text: "heya", post_id: post.id})

    query = from(p in Post, join: c in assoc(p, :comments), select: {p, c}, order_by: p.id)
    [{^post, ^c1}, {^post, ^c2}] = TestRepo.all(query)
  end

  test "has_one association join" do
    post1 = TestRepo.insert!(%Post{title: "1"})
    post2 = TestRepo.insert!(%Post{title: "1"})
    user = TestRepo.insert!(%User{})
    p1 = TestRepo.insert!(%Permalink{url: "hey", user_id: user.id, post_id: post1.id})
    p2 = TestRepo.insert!(%Permalink{url: "heya", user_id: user.id, post_id: post2.id})

    query = from(p in User, join: c in assoc(p, :permalink), select: {p, c}, order_by: c.id)
    [{^user, ^p1}, {^user, ^p2}] = TestRepo.all(query)
  end

  test "belongs_to association join" do
    post1 = TestRepo.insert!(%Post{title: "1"})
    post2 = TestRepo.insert!(%Post{title: "1"})
    user = TestRepo.insert!(%User{})
    p1 = TestRepo.insert!(%Permalink{url: "hey", user_id: user.id, post_id: post1.id})
    p2 = TestRepo.insert!(%Permalink{url: "heya", user_id: user.id, post_id: post2.id})

    query = from(p in Permalink, join: c in assoc(p, :user), select: {p, c}, order_by: p.id)
    [{^p1, ^user}, {^p2, ^user}] = TestRepo.all(query)
  end

  test "has_many through association join" do
    p1 = TestRepo.insert!(%Post{})
    p2 = TestRepo.insert!(%Post{})

    u1 = TestRepo.insert!(%User{name: "zzz"})
    u2 = TestRepo.insert!(%User{name: "aaa"})

    %Comment{} = TestRepo.insert!(%Comment{post_id: p1.id, author_id: u1.id})
    %Comment{} = TestRepo.insert!(%Comment{post_id: p1.id, author_id: u1.id})
    %Comment{} = TestRepo.insert!(%Comment{post_id: p1.id, author_id: u2.id})
    %Comment{} = TestRepo.insert!(%Comment{post_id: p2.id, author_id: u2.id})

    query = from p in Post, join: a in assoc(p, :comments_authors), select: {p, a}, order_by: [p.id, a.name]
    assert [{^p1, ^u2}, {^p1, ^u1}, {^p1, ^u1}, {^p2, ^u2}] = TestRepo.all(query)
  end

  test "has_many through nested association joins" do
    u1 = TestRepo.insert!(%User{name: "Alice"})
    u2 = TestRepo.insert!(%User{name: "John"})

    p1 = TestRepo.insert!(%Post{title: "p1", author_id: u1.id})
    p2 = TestRepo.insert!(%Post{title: "p2", author_id: u1.id})

    TestRepo.insert!(%Comment{text: "c1", author_id: u1.id, post_id: p1.id})
    TestRepo.insert!(%Comment{text: "c2", author_id: u2.id, post_id: p1.id})
    TestRepo.insert!(%Comment{text: "c3", author_id: u2.id, post_id: p2.id})
    TestRepo.insert!(%Comment{text: "c4", post_id: p2.id})
    TestRepo.insert!(%Comment{text: "c5", author_id: u1.id, post_id: p2.id})

    assert %{
             comments: [
               %{text: "c1"},
               %{text: "c5"}
             ],
             posts: [
               %{title: "p1"} = p1,
               %{title: "p2"} = p2
             ]
           } =
             from(u in User)
             |> join(:left, [u], p in assoc(u, :posts))
             |> join(:left, [u], c in assoc(u, :comments))
             |> join(:left, [_, p], c in assoc(p, :comments))
             |> preload(
               [user, posts, comments, post_comments],
               comments: comments,
               posts: {posts, comments: {post_comments, :author}}
             )
             |> TestRepo.get(u1.id)

    assert [
             %{text: "c1", author: %{name: "Alice"}},
             %{text: "c2", author: %{name: "John"}}
           ] = Enum.sort_by(p1.comments, & &1.text)

    assert [
             %{text: "c3", author: %{name: "John"}},
             %{text: "c4", author: nil},
             %{text: "c5", author: %{name: "Alice"}}
           ] = Enum.sort_by(p2.comments, & &1.text)
  end

  test "many_to_many association join" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    _p = TestRepo.insert!(%Post{title: "3"})
    u1 = TestRepo.insert!(%User{name: "john"})
    u2 = TestRepo.insert!(%User{name: "mary"})

    TestRepo.insert_all "posts_users", [[post_id: p1.id, user_id: u1.id],
                                        [post_id: p1.id, user_id: u2.id],
                                        [post_id: p2.id, user_id: u2.id]]

    query = from(p in Post, join: u in assoc(p, :users), select: {p, u}, order_by: p.id)
    [{^p1, ^u1}, {^p1, ^u2}, {^p2, ^u2}] = TestRepo.all(query)
  end

  ## Association preload

  test "has_many assoc selector" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})

    c1 = TestRepo.insert!(%Comment{text: "1", post_id: p1.id})
    c2 = TestRepo.insert!(%Comment{text: "2", post_id: p1.id})
    c3 = TestRepo.insert!(%Comment{text: "3", post_id: p2.id})

    # Without on
    query = from(p in Post, join: c in assoc(p, :comments), preload: [comments: c])
    [p1, p2] = TestRepo.all(query)
    assert p1.comments == [c1, c2]
    assert p2.comments == [c3]

    # With on
    query = from(p in Post, left_join: c in assoc(p, :comments),
                            on: p.title == c.text, preload: [comments: c])
    [p1, p2] = TestRepo.all(query)
    assert p1.comments == [c1]
    assert p2.comments == []
  end

  test "has_one assoc selector" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})

    pl1 = TestRepo.insert!(%Permalink{url: "1", post_id: p1.id})
    _pl = TestRepo.insert!(%Permalink{url: "2"})
    pl3 = TestRepo.insert!(%Permalink{url: "3", post_id: p2.id})

    query = from(p in Post, join: pl in assoc(p, :permalink), preload: [permalink: pl])
    assert [post1, post3] = TestRepo.all(query)

    assert post1.permalink == pl1
    assert post3.permalink == pl3
  end

  test "belongs_to assoc selector" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})

    TestRepo.insert!(%Permalink{url: "1", post_id: p1.id})
    TestRepo.insert!(%Permalink{url: "2"})
    TestRepo.insert!(%Permalink{url: "3", post_id: p2.id})

    query = from(pl in Permalink, left_join: p in assoc(pl, :post), preload: [post: p], order_by: pl.id)
    assert [pl1, pl2, pl3] = TestRepo.all(query)

    assert pl1.post == p1
    refute pl2.post
    assert pl3.post == p2
  end

  test "many_to_many assoc selector" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    _p = TestRepo.insert!(%Post{title: "3"})
    u1 = TestRepo.insert!(%User{name: "1"})
    u2 = TestRepo.insert!(%User{name: "2"})

    TestRepo.insert_all "posts_users", [[post_id: p1.id, user_id: u1.id],
                                        [post_id: p1.id, user_id: u2.id],
                                        [post_id: p2.id, user_id: u2.id]]

    # Without on
    query = from(p in Post, left_join: u in assoc(p, :users), preload: [users: u], order_by: p.id)
    [p1, p2, p3] = TestRepo.all(query)
    assert Enum.sort_by(p1.users, & &1.name) == [u1, u2]
    assert p2.users == [u2]
    assert p3.users == []

    # With on
    query = from(p in Post, left_join: u in assoc(p, :users), on: p.title == u.name,
                            preload: [users: u], order_by: p.id)
    [p1, p2, p3] = TestRepo.all(query)
    assert p1.users == [u1]
    assert p2.users == [u2]
    assert p3.users == []
  end

  test "has_many through assoc selector" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})

    u1 = TestRepo.insert!(%User{name: "1"})
    u2 = TestRepo.insert!(%User{name: "2"})

    TestRepo.insert!(%Comment{post_id: p1.id, author_id: u1.id})
    TestRepo.insert!(%Comment{post_id: p1.id, author_id: u1.id})
    TestRepo.insert!(%Comment{post_id: p1.id, author_id: u2.id})
    TestRepo.insert!(%Comment{post_id: p2.id, author_id: u2.id})

    # Without on
    query = from(p in Post, left_join: ca in assoc(p, :comments_authors),
                            preload: [comments_authors: ca])
    [p1, p2] = TestRepo.all(query)
    assert Enum.sort_by(p1.comments_authors, & &1.id) == [u1, u2]
    assert p2.comments_authors == [u2]

    # With on
    query = from(p in Post, left_join: ca in assoc(p, :comments_authors),
                            on: ca.name == p.title, preload: [comments_authors: ca])
    [p1, p2] = TestRepo.all(query)
    assert p1.comments_authors == [u1]
    assert p2.comments_authors == [u2]
  end

  test "has_many through-through assoc selector" do
    %Post{id: pid1} = TestRepo.insert!(%Post{})
    %Post{id: pid2} = TestRepo.insert!(%Post{})

    %Permalink{} = TestRepo.insert!(%Permalink{post_id: pid1, url: "1"})
    %Permalink{} = TestRepo.insert!(%Permalink{post_id: pid2, url: "2"})

    %User{id: uid1} = TestRepo.insert!(%User{})
    %User{id: uid2} = TestRepo.insert!(%User{})

    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid2})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid2, author_id: uid2})

    query = from(p in Permalink, left_join: ca in assoc(p, :post_comments_authors),
                                 preload: [post_comments_authors: ca], order_by: ca.id)

    [l1, l2] = TestRepo.all(query)
    [u1, u2] = l1.post_comments_authors
    assert u1.id == uid1
    assert u2.id == uid2

    [u2] = l2.post_comments_authors
    assert u2.id == uid2

    # Insert some intermediary joins to check indexes won't be shuffled
    query = from(p in Permalink,
                    left_join: assoc(p, :post),
                    left_join: ca in assoc(p, :post_comments_authors),
                    left_join: assoc(p, :post),
                    left_join: assoc(p, :post),
                    preload: [post_comments_authors: ca], order_by: ca.id)

    [l1, l2] = TestRepo.all(query)
    [u1, u2] = l1.post_comments_authors
    assert u1.id == uid1
    assert u2.id == uid2

    [u2] = l2.post_comments_authors
    assert u2.id == uid2
  end

  ## Nested

  test "nested assoc" do
    %Post{id: pid1} = TestRepo.insert!(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert!(%Post{title: "2"})

    %User{id: uid1} = TestRepo.insert!(%User{name: "1"})
    %User{id: uid2} = TestRepo.insert!(%User{name: "2"})

    %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: pid1, author_id: uid1})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: pid1, author_id: uid2})
    %Comment{id: cid3} = TestRepo.insert!(%Comment{text: "3", post_id: pid2, author_id: uid2})

    # use multiple associations to force parallel preloader
    query = from p in Post,
      left_join: c in assoc(p, :comments),
      left_join: u in assoc(c, :author),
      order_by: [p.id, c.id, u.id],
      preload: [:permalink, comments: {c, author: {u, [:comments, :custom]}}],
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
    %Post{id: pid1} = TestRepo.insert!(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert!(%Post{title: "2"})
    %Post{id: pid3} = TestRepo.insert!(%Post{title: "2"})

    %User{id: uid1} = TestRepo.insert!(%User{name: "1"})
    %User{id: uid2} = TestRepo.insert!(%User{name: "2"})

    %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: pid1, author_id: uid1})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: pid1, author_id: nil})
    %Comment{id: cid3} = TestRepo.insert!(%Comment{text: "3", post_id: pid3, author_id: uid2})

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

  test "nested assoc with child preload" do
    %Post{id: pid1} = TestRepo.insert!(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert!(%Post{title: "2"})

    %User{id: uid1} = TestRepo.insert!(%User{name: "1"})
    %User{id: uid2} = TestRepo.insert!(%User{name: "2"})

    %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: pid1, author_id: uid1})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: pid1, author_id: uid2})
    %Comment{id: cid3} = TestRepo.insert!(%Comment{text: "3", post_id: pid2, author_id: uid2})

    query = from p in Post,
      left_join: c in assoc(p, :comments),
      order_by: [p.id, c.id],
      preload: [comments: {c, :author}],
      select: p

    assert [p1, p2] = TestRepo.all(query)
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

  test "nested assoc with sibling preload" do
    %Post{id: pid1} = TestRepo.insert!(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert!(%Post{title: "2"})

    %Permalink{id: plid1} = TestRepo.insert!(%Permalink{url: "1", post_id: pid2})

    %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: pid1})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: pid2})
    %Comment{id: _}    = TestRepo.insert!(%Comment{text: "3", post_id: pid2})

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

  test "mixing regular join and assoc selector" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})

    c1 = TestRepo.insert!(%Comment{text: "1", post_id: p1.id})
    c2 = TestRepo.insert!(%Comment{text: "2", post_id: p1.id})
    c3 = TestRepo.insert!(%Comment{text: "3", post_id: p2.id})

    pl1 = TestRepo.insert!(%Permalink{url: "1", post_id: p1.id})
    _pl = TestRepo.insert!(%Permalink{url: "2"})
    pl3 = TestRepo.insert!(%Permalink{url: "3", post_id: p2.id})

    # Without on
    query = from(p in Post, join: pl in assoc(p, :permalink),
                            join: c in assoc(p, :comments),
                            preload: [permalink: pl],
                            select: {p, c})
    [{p1, ^c1}, {p1, ^c2}, {p2, ^c3}] = TestRepo.all(query)
    assert p1.permalink == pl1
    assert p2.permalink == pl3
  end

  test "association with composite pk join" do
    post = TestRepo.insert!(%Post{title: "1"})
    user = TestRepo.insert!(%User{name: "1"})
    TestRepo.insert!(%PostUserCompositePk{post_id: post.id, user_id: user.id})

    query = from(p in Post, join: a in assoc(p, :post_user_composite_pk),
                 preload: [post_user_composite_pk: a], select: p)
    assert [post] = TestRepo.all(query)
    assert post.post_user_composite_pk
  end

  test "joining a through association with a nested preloads" do
    post = TestRepo.insert!(%Post{title: "1"})
    user = TestRepo.insert!(%User{name: "1"})
    TestRepo.insert!(%Comment{text: "1", post_id: post.id})
    TestRepo.insert!(%Permalink{post_id: post.id, user_id: user.id})

    query =
      from c in Comment,
        join: pp in assoc(c, :post_permalink),
        join: u in assoc(pp, :user),
        preload: [post_permalink: {pp, [:post, user: u]}]

    [comment] = TestRepo.all(query)

    assert not Ecto.assoc_loaded?(comment.post)
    assert %Permalink{user: %User{}, post: %Post{}} = comment.post_permalink
  end

  test "joining multiple through associations with a nested preloads" do
    post = TestRepo.insert!(%Post{title: "1"})
    user = TestRepo.insert!(%User{name: "1"})
    TestRepo.insert!(%Comment{text: "1", post_id: post.id, author_id: user.id})
    TestRepo.insert!(%Permalink{post_id: post.id, user_id: user.id})

    query =
      from c in Comment,
        join: pp in assoc(c, :post_permalink),
        join: ap in assoc(c, :author_permalink),
        join: u1 in assoc(pp, :user),
        join: u2 in assoc(ap, :user),
        preload: [post_permalink: {pp, [:post, user: u1]}, author_permalink: {ap, [:post, user: u2]}]

    [comment] = TestRepo.all(query)

    assert not Ecto.assoc_loaded?(comment.post)
    assert not Ecto.assoc_loaded?(comment.author)
    assert %Permalink{user: %User{}, post: %Post{}} = comment.post_permalink
    assert %Permalink{user: %User{}, post: %Post{}} = comment.author_permalink
  end

  test "joining nested through associations with a nested preloads" do
    user = TestRepo.insert!(%User{name: "1"})
    post = TestRepo.insert!(%Post{title: "1", author_id: user.id})
    TestRepo.insert!(%Comment{text: "1", post_id: post.id})
    TestRepo.insert!(%Permalink{post_id: post.id, user_id: user.id})

    query =
      from c in Comment,
        join: pp in assoc(c, :post_permalink),
        join: up in assoc(pp, :user_posts),
        preload: [post_permalink: {pp, [:post, user_posts: {up, :comments}]}]

    [comment] = TestRepo.all(query)

    assert not Ecto.assoc_loaded?(comment.post)
    assert %Permalink{post: %Post{}, user_posts: [%Post{}]} = comment.post_permalink
    assert not Ecto.assoc_loaded?(comment.post_permalink.user)
  end

  test "joining and preloading through a subquery" do
    %{id: p_id} = TestRepo.insert!(%Post{})
    %{id: c1_id} = TestRepo.insert!(%Comment{post_id: p_id})
    %{id: c2_id} = TestRepo.insert!(%Comment{post_id: p_id})

    q =
      from p1 in Post,
        left_join: u in User,
        on: p1.author_id == u.id,
        inner_join: c in subquery(from c in Comment),
        on: p1.id == c.post_id,
        join: p2 in Post,
        on: c.post_id == p2.id,
        preload: [author: u, force_comments: {c, post: p2}]

    assert [%Post{id: ^p_id, force_comments: comments}] = TestRepo.all(q)
    [comment1, comment2] = Enum.sort_by(comments, & &1.id)
    assert %Comment{id: ^c1_id, post: %Post{id: ^p_id}} = comment1
    assert %Comment{id: ^c2_id, post: %Post{id: ^p_id}} = comment2
  end
end
