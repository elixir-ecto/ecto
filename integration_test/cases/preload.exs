defmodule Ecto.Integration.PreloadTest do
  use Ecto.Integration.Case

  alias Ecto.Integration.TestRepo
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
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    p3 = TestRepo.insert!(%Post{title: "3"})

    %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: p1.id})
    %Comment{id: cid3} = TestRepo.insert!(%Comment{text: "3", post_id: p2.id})
    %Comment{id: cid4} = TestRepo.insert!(%Comment{text: "4", post_id: p2.id})

    assert %Ecto.Association.NotLoaded{} = p1.comments

    # With custom query
    assert [pe3, pe1, pe2] = TestRepo.preload([p3, p1, p2],
                                              comments: from(c in Comment, where: false))
    assert [] = pe1.comments
    assert [] = pe2.comments
    assert [] = pe3.comments

    # With assoc query
    assert [p3, p1, p2] = TestRepo.preload([p3, p1, p2], :comments)
    assert [%Comment{id: ^cid1}, %Comment{id: ^cid2}] = p1.comments |> sort_by_id
    assert [%Comment{id: ^cid3}, %Comment{id: ^cid4}] = p2.comments |> sort_by_id
    assert [] = p3.comments
  end

  test "preload has_one" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    p3 = TestRepo.insert!(%Post{title: "3"})

    %Permalink{id: pid1} = TestRepo.insert!(%Permalink{url: "1", post_id: p1.id})
    %Permalink{}         = TestRepo.insert!(%Permalink{url: "2", post_id: nil})
    %Permalink{id: pid3} = TestRepo.insert!(%Permalink{url: "3", post_id: p3.id})

    assert %Ecto.Association.NotLoaded{} = p1.permalink
    assert %Ecto.Association.NotLoaded{} = p2.permalink

    # With custom query
    assert [pe3, pe1, pe2] = TestRepo.preload([p3, p1, p2],
                                              permalink: from(p in Permalink, where: false))
    refute pe1.permalink
    refute pe2.permalink
    refute pe3.permalink

    # With assoc query
    assert [p3, p1, p2] = TestRepo.preload([p3, p1, p2], :permalink)
    assert %Permalink{id: ^pid1} = p1.permalink
    refute p2.permalink
    assert %Permalink{id: ^pid3} = p3.permalink
  end

  test "preload belongs_to" do
    %Post{id: pid1} = TestRepo.insert!(%Post{title: "1"})
    TestRepo.insert!(%Post{title: "2"})
    %Post{id: pid3} = TestRepo.insert!(%Post{title: "3"})

    pl1 = TestRepo.insert!(%Permalink{url: "1", post_id: pid1})
    pl2 = TestRepo.insert!(%Permalink{url: "2", post_id: nil})
    pl3 = TestRepo.insert!(%Permalink{url: "3", post_id: pid3})

    assert %Ecto.Association.NotLoaded{} = pl1.post

    assert [ple3, ple1, ple2] = TestRepo.preload([pl3, pl1, pl2],
                                                 post: from(p in Post, where: false))
    refute ple1.post
    refute ple2.post
    refute ple3.post

    assert [pl3, pl1, pl2] = TestRepo.preload([pl3, pl1, pl2], :post)
    assert %Post{id: ^pid1} = pl1.post
    refute pl2.post
    assert %Post{id: ^pid3} = pl3.post
  end

  test "preload has_many through" do
    %Post{id: pid1} = p1 = TestRepo.insert!(%Post{})
    %Post{id: pid2} = p2 = TestRepo.insert!(%Post{})

    %User{id: uid1} = TestRepo.insert!(%User{})
    %User{id: uid2} = TestRepo.insert!(%User{})

    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid2})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid2, author_id: uid2})

    p1 = TestRepo.preload(p1, :comments_authors)

    # Through was preloaded
    [u1, u2] = p1.comments_authors |> sort_by_id
    assert u1.id == uid1
    assert u2.id == uid2

    # But we also preloaded everything along the way
    assert [c1, c2, c3] = p1.comments |> sort_by_id
    assert c1.author.id == uid1
    assert c2.author.id == uid1
    assert c3.author.id == uid2

    [p1, p2] = TestRepo.preload([p1, p2], :comments_authors)

    # Through was preloaded
    [u1, u2] = p1.comments_authors |> sort_by_id
    assert u1.id == uid1
    assert u2.id == uid2

    [u2] = p2.comments_authors
    assert u2.id == uid2

    # But we also preloaded everything along the way
    assert [c1, c2, c3] = p1.comments |> sort_by_id
    assert c1.author.id == uid1
    assert c2.author.id == uid1
    assert c3.author.id == uid2

    assert [c4] = p2.comments
    assert c4.author.id == uid2
  end

  test "preload has_one through" do
    %Post{id: pid1} = TestRepo.insert!(%Post{})
    %Post{id: pid2} = TestRepo.insert!(%Post{})

    %Permalink{id: lid1} = TestRepo.insert!(%Permalink{post_id: pid1})
    %Permalink{id: lid2} = TestRepo.insert!(%Permalink{post_id: pid2})

    %Comment{} = c1 = TestRepo.insert!(%Comment{post_id: pid1})
    %Comment{} = c2 = TestRepo.insert!(%Comment{post_id: pid1})
    %Comment{} = c3 = TestRepo.insert!(%Comment{post_id: pid2})

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
    %Post{id: pid1} = TestRepo.insert!(%Post{})
    %Post{id: pid2} = TestRepo.insert!(%Post{})

    %Permalink{} = l1 = TestRepo.insert!(%Permalink{post_id: pid1})
    %Permalink{} = l2 = TestRepo.insert!(%Permalink{post_id: pid2})

    %User{id: uid1} = TestRepo.insert!(%User{name: "foo"})
    %User{id: uid2} = TestRepo.insert!(%User{name: "bar"})

    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid2})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid2, author_id: uid2})

    # With custom query
    [le1, le2] = TestRepo.preload([l1, l2],
                                  post_comments_authors: from(u in User, where: u.name == "foo"))
    assert [u1] = le1.post_comments_authors
    assert u1.id == uid1
    assert [] = le2.post_comments_authors

    # With assoc query
    [l1, l2] = TestRepo.preload([l1, l2], :post_comments_authors)

    # Through was preloaded
    [u1, u2] = l1.post_comments_authors |> sort_by_id
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
    %Post{id: pid1} = p1 = TestRepo.insert!(%Post{})
    %Post{id: pid2} = p2 = TestRepo.insert!(%Post{})

    %User{id: uid1} = TestRepo.insert!(%User{})
    %User{id: uid2} = TestRepo.insert!(%User{})

    %Comment{} = c1 = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = c2 = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = c3 = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid2})
    %Comment{} = c4 = TestRepo.insert!(%Comment{post_id: pid2, author_id: uid2})

    [p1, p2] = TestRepo.preload([p1, p2], [:permalink, comments_authors: :comments])

    # Through was preloaded
    [u1, u2] = p1.comments_authors |> sort_by_id
    assert u1.id == uid1
    assert u2.id == uid2
    assert [c1, c2] == u1.comments |> sort_by_id

    [u2] = p2.comments_authors
    assert u2.id == uid2
    assert [c3, c4] == u2.comments |> sort_by_id
  end

  test "preload belongs_to with shared assocs" do
    %Post{id: pid1} = TestRepo.insert!(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert!(%Post{title: "2"})

    c1 = TestRepo.insert!(%Comment{text: "1", post_id: pid1})
    c2 = TestRepo.insert!(%Comment{text: "2", post_id: pid1})
    c3 = TestRepo.insert!(%Comment{text: "3", post_id: pid2})

    assert [c3, c1, c2] = TestRepo.preload([c3, c1, c2], :post)
    assert %Post{id: ^pid1} = c1.post
    assert %Post{id: ^pid1} = c2.post
    assert %Post{id: ^pid2} = c3.post
  end

  @tag :invalid_prefix
  test "preload custom prefix" do
    p = TestRepo.insert!(%Post{title: "1"})
    p = Ecto.Model.put_source(p, "posts", "this_surely_does_not_exist")
    # This preload should fail because it points to a prefix that does not exist
    assert catch_error(TestRepo.preload(p, [:comments]))
  end

  test "preload nested" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})

    TestRepo.insert!(%Comment{text: "1", post_id: p1.id})
    TestRepo.insert!(%Comment{text: "2", post_id: p1.id})
    TestRepo.insert!(%Comment{text: "3", post_id: p2.id})
    TestRepo.insert!(%Comment{text: "4", post_id: p2.id})

    assert [p2, p1] = TestRepo.preload([p2, p1], [comments: :post])
    assert [c1, c2] = p1.comments
    assert [c3, c4] = p2.comments
    assert p1.id == c1.post.id
    assert p1.id == c2.post.id
    assert p2.id == c3.post.id
    assert p2.id == c4.post.id
  end

  test "preload nested via custom query" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})

    TestRepo.insert!(%Comment{text: "1", post_id: p1.id})
    TestRepo.insert!(%Comment{text: "2", post_id: p1.id})
    TestRepo.insert!(%Comment{text: "3", post_id: p2.id})
    TestRepo.insert!(%Comment{text: "4", post_id: p2.id})

    query = from(c in Comment, preload: :post, order_by: [desc: c.text])
    assert [p2, p1] = TestRepo.preload([p2, p1], comments: query)
    assert [c2, c1] = p1.comments
    assert [c4, c3] = p2.comments
    assert p1.id == c1.post.id
    assert p1.id == c2.post.id
    assert p2.id == c3.post.id
    assert p2.id == c4.post.id
  end

  test "preload has_many with no associated entries" do
    p = TestRepo.insert!(%Post{title: "1"})
    p = TestRepo.preload(p, :comments)

    assert p.title == "1"
    assert p.comments == []
  end

  test "preload has_one with no associated entries" do
    p = TestRepo.insert!(%Post{title: "1"})
    p = TestRepo.preload(p, :permalink)

    assert p.title == "1"
    assert p.permalink == nil
  end

  test "preload belongs_to with no associated entry" do
    c = TestRepo.insert!(%Comment{text: "1"})
    c = TestRepo.preload(c, :post)

    assert c.text == "1"
    assert c.post == nil
  end

  test "preload with binary_id" do
    c = TestRepo.insert!(%Custom{})
    u = TestRepo.insert!(%User{custom_id: c.bid})

    u = TestRepo.preload(u, :custom)
    assert u.custom.bid == c.bid
  end

  test "preload skips already loaded" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})

    %Comment{id: _}    = TestRepo.insert!(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: p2.id})

    assert %Ecto.Association.NotLoaded{} = p1.comments
    p1 = %{p1 | comments: []}

    assert [p1, p2] = TestRepo.preload([p1, p2], :comments)
    assert [] = p1.comments
    assert [%Comment{id: ^cid2}] = p2.comments
  end

  test "preload keyword query" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    TestRepo.insert!(%Post{title: "3"})

    %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: p1.id})
    %Comment{id: cid3} = TestRepo.insert!(%Comment{text: "3", post_id: p2.id})
    %Comment{id: cid4} = TestRepo.insert!(%Comment{text: "4", post_id: p2.id})

    # Regular query
    query = from(p in Post, preload: [:comments], select: p)

    assert [p1, p2, p3] = TestRepo.all(query)
    assert [%Comment{id: ^cid1}, %Comment{id: ^cid2}] = p1.comments |> sort_by_id
    assert [%Comment{id: ^cid3}, %Comment{id: ^cid4}] = p2.comments |> sort_by_id
    assert [] = p3.comments

    # Query with interpolated preload query
    query = from(p in Post, preload: [comments: ^from(c in Comment, where: false)], select: p)

    assert [p1, p2, p3] = TestRepo.all(query)
    assert [] = p1.comments
    assert [] = p2.comments
    assert [] = p3.comments

    # Now let's use an interpolated preload too
    comments = [:comments]
    query = from(p in Post, preload: ^comments, select: {0, [p], 1, 2})

    posts = TestRepo.all(query)
    [p1, p2, p3] = Enum.map(posts, fn {0, [p], 1, 2} -> p end)

    assert [%Comment{id: ^cid1}, %Comment{id: ^cid2}] = p1.comments |> sort_by_id
    assert [%Comment{id: ^cid3}, %Comment{id: ^cid4}] = p2.comments |> sort_by_id
    assert [] = p3.comments
  end

  defp sort_by_id(values) do
    Enum.sort_by(values, &(&1.id))
  end
end
