defmodule Ecto.Integration.JoinsTest do
  use Ecto.Integration.Case

  alias Ecto.Integration.TestRepo
  import Ecto.Query

  alias Ecto.Integration.Post
  alias Ecto.Integration.Comment
  alias Ecto.Integration.Permalink
  alias Ecto.Integration.User

  @tag :update_with_join
  test "update all with joins" do
    user    = TestRepo.insert!(%User{name: "Tester"})
    post    = TestRepo.insert!(%Post{title: "foo"})
    comment = TestRepo.insert!(%Comment{text: "hey", author_id: user.id, post_id: post.id})

    query = from(c in Comment, join: u in User, on: u.id == c.author_id,
                               where: c.post_id in ^[post.id])

    assert {1, nil} = TestRepo.update_all(query, set: [text: "hoo"])
    assert %Comment{text: "hoo"} = TestRepo.get(Comment, comment.id)
  end

  @tag :delete_with_join
  test "delete all with joins" do
    user = TestRepo.insert!(%User{name: "Tester"})
    post = TestRepo.insert!(%Post{title: "foo"})
    TestRepo.insert!(%Comment{text: "hey", author_id: user.id, post_id: post.id})
    TestRepo.insert!(%Comment{text: "foo", author_id: user.id, post_id: post.id})
    TestRepo.insert!(%Comment{text: "bar", author_id: user.id})

    query = from(c in Comment, join: u in User, on: u.id == c.author_id,
                               where: c.post_id in ^[post.id])
    assert {2, nil} = TestRepo.delete_all(query)
    assert [%Comment{}] = TestRepo.all(Comment)
  end

  test "joins" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    c1 = TestRepo.insert!(%Permalink{url: "1", post_id: p2.id})

    query = from(p in Post, join: c in assoc(p, :permalink), order_by: p.id, select: {p, c})
    assert [{^p2, ^c1}] = TestRepo.all(query)

    query = from(p in Post, left_join: c in assoc(p, :permalink), order_by: p.id, select: {p, c})
    assert [{^p1, nil}, {^p2, ^c1}] = TestRepo.all(query)
  end

  @tag :right_join
  test "right joins with missing entries" do
    %Post{id: pid1} = TestRepo.insert!(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert!(%Post{title: "2"})

    %Permalink{id: plid1} = TestRepo.insert!(%Permalink{url: "1", post_id: pid2})

    %Comment{id: _} = TestRepo.insert!(%Comment{text: "1", post_id: pid1})
    %Comment{id: _} = TestRepo.insert!(%Comment{text: "2", post_id: pid2})
    %Comment{id: _} = TestRepo.insert!(%Comment{text: "3", post_id: nil})

    query = from(p in Post, right_join: c in assoc(p, :comments),
                 preload: :permalink, order_by: c.id)
    assert [p1, p2, nil] = TestRepo.all(query)
    assert p1.id == pid1
    assert p2.id == pid2

    assert p1.permalink == nil
    assert p2.permalink.id == plid1
  end

  test "has_many association join" do
    post = TestRepo.insert!(%Post{title: "1", text: "hi"})
    c1 = TestRepo.insert!(%Comment{text: "hey", post_id: post.id})
    c2 = TestRepo.insert!(%Comment{text: "heya", post_id: post.id})

    query = from(p in Post, join: c in assoc(p, :comments), select: {p, c}, order_by: p.id)
    [{^post, ^c1}, {^post, ^c2}] = TestRepo.all(query)
  end

  test "has_one association join" do
    post = TestRepo.insert!(%Post{title: "1", text: "hi"})
    p1 = TestRepo.insert!(%Permalink{url: "hey", post_id: post.id})
    p2 = TestRepo.insert!(%Permalink{url: "heya", post_id: post.id})

    query = from(p in Post, join: c in assoc(p, :permalink), select: {p, c}, order_by: c.id)
    [{^post, ^p1}, {^post, ^p2}] = TestRepo.all(query)
  end

  test "belongs_to association join" do
    post = TestRepo.insert!(%Post{title: "1"})
    p1 = TestRepo.insert!(%Permalink{url: "hey", post_id: post.id})
    p2 = TestRepo.insert!(%Permalink{url: "heya", post_id: post.id})

    query = from(p in Permalink, join: c in assoc(p, :post), select: {p, c}, order_by: p.id)
    [{^p1, ^post}, {^p2, ^post}] = TestRepo.all(query)
  end

  test "has_many through assoc" do
    %Post{id: pid1} = p1 = TestRepo.insert!(%Post{})
    %Post{id: pid2} = p2 = TestRepo.insert!(%Post{})

    %User{id: uid1} = TestRepo.insert!(%User{name: "zzz"})
    %User{id: uid2} = TestRepo.insert!(%User{name: "aaa"})

    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid2})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid2, author_id: uid2})

    [u2, u1] = TestRepo.all Ecto.Model.assoc([p1, p2], :comments_authors)
                            |> order_by([a], a.name)
    assert u1.id == uid1
    assert u2.id == uid2
  end

  ## Preload assocs

  test "has_many assoc selector" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "1"})

    %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: p1.id})
    %Comment{id: cid3} = TestRepo.insert!(%Comment{text: "3", post_id: p2.id})

    query = from(p in Post, join: c in assoc(p, :comments), preload: [comments: c])
    assert [post1, post2] = TestRepo.all(query)
    assert [%Comment{id: ^cid1}, %Comment{id: ^cid2}] = post1.comments
    assert [%Comment{id: ^cid3}] = post2.comments
  end

  test "has_one assoc selector" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})

    %Permalink{id: pid1} = TestRepo.insert!(%Permalink{url: "1", post_id: p1.id})
    %Permalink{}         = TestRepo.insert!(%Permalink{url: "2"})
    %Permalink{id: pid3} = TestRepo.insert!(%Permalink{url: "3", post_id: p2.id})

    query = from(p in Post, join: pl in assoc(p, :permalink), preload: [permalink: pl])
    assert [post1, post3] = TestRepo.all(query)

    assert %Permalink{id: ^pid1} = post1.permalink
    assert %Permalink{id: ^pid3} = post3.permalink
  end

  test "belongs_to assoc selector" do
    %Post{id: pid1} = TestRepo.insert!(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert!(%Post{title: "2"})

    TestRepo.insert!(%Permalink{url: "1", post_id: pid1})
    TestRepo.insert!(%Permalink{url: "2"})
    TestRepo.insert!(%Permalink{url: "3", post_id: pid2})

    query = from(pl in Permalink, left_join: p in assoc(pl, :post), preload: [post: p], order_by: pl.id)
    assert [p1, p2, p3] = TestRepo.all(query)

    assert %Post{id: ^pid1} = p1.post
    refute p2.post
    assert %Post{id: ^pid2} = p3.post
  end

  test "has_many through assoc selector" do
    %Post{id: pid1} = TestRepo.insert!(%Post{})
    %Post{id: pid2} = TestRepo.insert!(%Post{})

    %User{id: uid1} = TestRepo.insert!(%User{})
    %User{id: uid2} = TestRepo.insert!(%User{})

    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid2})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid2, author_id: uid2})

    query = from(p in Post, left_join: ca in assoc(p, :comments_authors),
                            preload: [comments_authors: ca])
    [p1, p2] = TestRepo.all(query)

    [u1, u2] = p1.comments_authors
    assert u1.id == uid1
    assert u2.id == uid2

    [u2] = p2.comments_authors
    assert u2.id == uid2
  end

  test "has_many through-through assoc selector" do
    %Post{id: pid1} = TestRepo.insert!(%Post{})
    %Post{id: pid2} = TestRepo.insert!(%Post{})

    %Permalink{} = TestRepo.insert!(%Permalink{post_id: pid1})
    %Permalink{} = TestRepo.insert!(%Permalink{post_id: pid2})

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

  test "nested assoc" do
    %Post{id: pid1} = TestRepo.insert!(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert!(%Post{title: "2"})

    %User{id: uid1} = TestRepo.insert!(%User{name: "1"})
    %User{id: uid2} = TestRepo.insert!(%User{name: "2"})

    %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: pid1, author_id: uid1})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: pid1, author_id: uid2})
    %Comment{id: cid3} = TestRepo.insert!(%Comment{text: "3", post_id: pid2, author_id: uid2})

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

  test "assoc with preload" do
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
end
