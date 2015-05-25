defmodule Ecto.Integration.PreloadTest do
  use Ecto.Integration.Case

  require Ecto.Integration.TestRepo, as: TestRepo
  import Ecto.Query

  alias Ecto.Integration.Post
  alias Ecto.Integration.Comment
  alias Ecto.Integration.Permalink
  alias Ecto.Integration.User
  alias Ecto.Integration.Custom

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

    assert %Ecto.Association.NotLoaded{} = p1.comments

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

    assert %Ecto.Association.NotLoaded{} = p1.permalink
    assert %Ecto.Association.NotLoaded{} = p2.permalink

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

    assert %Ecto.Association.NotLoaded{} = pl1.post

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

  test "preload with uuid" do
    c = TestRepo.insert(%Custom{uuid: "0123456789abcdef"})
    u = TestRepo.insert(%User{custom_id: c.uuid})

    u = TestRepo.preload(u, :custom)
    assert u.custom.uuid == c.uuid
  end

  test "preload skips already loaded" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "2"})

    %Comment{id: _}    = TestRepo.insert(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert(%Comment{text: "2", post_id: p2.id})

    assert %Ecto.Association.NotLoaded{} = p1.comments
    p1 = %{p1 | comments: []}

    assert [p1, p2] = TestRepo.preload([p1, p2], :comments)
    assert [] = p1.comments
    assert [%Comment{id: ^cid2}] = p2.comments
  end

  test "preload has_many through" do
    %Post{id: pid1} = p1 = TestRepo.insert(%Post{})
    %Post{id: pid2} = p2 = TestRepo.insert(%Post{})

    %User{id: uid1} = TestRepo.insert(%User{})
    %User{id: uid2} = TestRepo.insert(%User{})

    %Comment{} = TestRepo.insert(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert(%Comment{post_id: pid1, author_id: uid2})
    %Comment{} = TestRepo.insert(%Comment{post_id: pid2, author_id: uid2})

    p1 = TestRepo.preload(p1, :comments_authors)

    # Through was preloaded
    [u1, u2] = p1.comments_authors
    assert u1.id == uid1
    assert u2.id == uid2

    # But we also preloaded everything along the way
    assert [c1, c2, c3] = p1.comments
    assert c1.author.id == uid1
    assert c2.author.id == uid1
    assert c3.author.id == uid2

    [p1, p2] = TestRepo.preload([p1, p2], :comments_authors)

    # Through was preloaded
    [u1, u2] = p1.comments_authors
    assert u1.id == uid1
    assert u2.id == uid2

    [u2] = p2.comments_authors
    assert u2.id == uid2

    # But we also preloaded everything along the way
    assert [c1, c2, c3] = p1.comments
    assert c1.author.id == uid1
    assert c2.author.id == uid1
    assert c3.author.id == uid2

    assert [c4] = p2.comments
    assert c4.author.id == uid2
  end

  test "preload has_one through" do
    %Post{id: pid1} = TestRepo.insert(%Post{})
    %Post{id: pid2} = TestRepo.insert(%Post{})

    %Permalink{id: lid1} = TestRepo.insert(%Permalink{post_id: pid1})
    %Permalink{id: lid2} = TestRepo.insert(%Permalink{post_id: pid2})

    %Comment{} = c1 = TestRepo.insert(%Comment{post_id: pid1})
    %Comment{} = c2 = TestRepo.insert(%Comment{post_id: pid1})
    %Comment{} = c3 = TestRepo.insert(%Comment{post_id: pid2})

    [c1, c2, c3] = TestRepo.preload([c1, c2, c3], :post_permalink)

    # Through was preloaded
    assert c1.post.id == pid1
    assert c1.post.permalink.id == lid1
    assert c1.post_permalink.id == lid1

    assert c2.post.id == pid1
    assert c2.post.permalink.id == lid1
    assert c2.post_permalink.id == lid1

    assert c3.post.id == pid2
    assert c3.post.permalink.id == lid2
    assert c3.post_permalink.id == lid2
  end

  test "preload has_many through-through" do
    %Post{id: pid1} = TestRepo.insert(%Post{})
    %Post{id: pid2} = TestRepo.insert(%Post{})

    %Permalink{} = l1 = TestRepo.insert(%Permalink{post_id: pid1})
    %Permalink{} = l2 = TestRepo.insert(%Permalink{post_id: pid2})

    %User{id: uid1} = TestRepo.insert(%User{})
    %User{id: uid2} = TestRepo.insert(%User{})

    %Comment{} = TestRepo.insert(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert(%Comment{post_id: pid1, author_id: uid2})
    %Comment{} = TestRepo.insert(%Comment{post_id: pid2, author_id: uid2})

    [l1, l2] = TestRepo.preload([l1, l2], :post_comments_authors)

    # Through was preloaded
    [u1, u2] = l1.post_comments_authors
    assert u1.id == uid1
    assert u2.id == uid2

    [u2] = l2.post_comments_authors
    assert u2.id == uid2

    # But we also preloaded everything along the way
    assert l1.post.id == pid1
    assert l1.post.comments != []

    assert l2.post.id == pid2
    assert l2.post.comments != []
  end

  test "preload has_many through nested" do
    %Post{id: pid1} = p1 = TestRepo.insert(%Post{})
    %Post{id: pid2} = p2 = TestRepo.insert(%Post{})

    %User{id: uid1} = TestRepo.insert(%User{})
    %User{id: uid2} = TestRepo.insert(%User{})

    %Comment{} = c1 = TestRepo.insert(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = c2 = TestRepo.insert(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = c3 = TestRepo.insert(%Comment{post_id: pid1, author_id: uid2})
    %Comment{} = c4 = TestRepo.insert(%Comment{post_id: pid2, author_id: uid2})

    [p1, p2] = TestRepo.preload([p1, p2], [:permalink, comments_authors: :comments])

    # Through was preloaded
    [u1, u2] = p1.comments_authors
    assert u1.id == uid1
    assert u2.id == uid2
    assert u1.comments == [c1, c2]

    [u2] = p2.comments_authors
    assert u2.id == uid2
    assert u2.comments == [c3, c4]
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

    query = from(p in Post, right_join: c in assoc(p, :comments),
                 preload: :permalink, order_by: c.id)
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

    query = from(pl in Permalink, left_join: p in assoc(pl, :post), preload: [post: p], order_by: pl.id)
    assert [p1, p2, p3] = TestRepo.all(query)

    assert %Post{id: ^pid1} = p1.post
    assert nil = p2.post
    assert %Post{id: ^pid2} = p3.post
  end

  test "has_many through assoc selector" do
    %Post{id: pid1} = TestRepo.insert(%Post{})
    %Post{id: pid2} = TestRepo.insert(%Post{})

    %User{id: uid1} = TestRepo.insert(%User{})
    %User{id: uid2} = TestRepo.insert(%User{})

    %Comment{} = TestRepo.insert(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert(%Comment{post_id: pid1, author_id: uid2})
    %Comment{} = TestRepo.insert(%Comment{post_id: pid2, author_id: uid2})

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
    %Post{id: pid1} = TestRepo.insert(%Post{})
    %Post{id: pid2} = TestRepo.insert(%Post{})

    %Permalink{} = TestRepo.insert(%Permalink{post_id: pid1})
    %Permalink{} = TestRepo.insert(%Permalink{post_id: pid2})

    %User{id: uid1} = TestRepo.insert(%User{})
    %User{id: uid2} = TestRepo.insert(%User{})

    %Comment{} = TestRepo.insert(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert(%Comment{post_id: pid1, author_id: uid2})
    %Comment{} = TestRepo.insert(%Comment{post_id: pid2, author_id: uid2})

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
