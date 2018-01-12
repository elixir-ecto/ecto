defmodule Ecto.Integration.PreloadTest do
  use Ecto.Integration.Case, async: Application.get_env(:ecto, :async_integration_tests, true)

  alias Ecto.Integration.TestRepo
  import Ecto.Query

  alias Ecto.Integration.Post
  alias Ecto.Integration.Comment
  alias Ecto.Integration.Permalink
  alias Ecto.Integration.User
  alias Ecto.Integration.Custom

  test "preload with parameter from select_merge" do
    p1 = TestRepo.insert!(%Post{title: "p1"})
    TestRepo.insert!(%Comment{text: "c1", post: p1})

    comments =
      from(c in Comment, select: struct(c, [:text]))
      |> select_merge([c], %{post_id: c.post_id})
      |> preload(:post)
      |> TestRepo.all()

    assert [%{text: "c1", post: %{title: "p1"}}] = comments
  end

  test "preload has_many" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    p3 = TestRepo.insert!(%Post{title: "3"})

    # We use the same text to expose bugs in preload sorting
    %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid3} = TestRepo.insert!(%Comment{text: "2", post_id: p2.id})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: p1.id})
    %Comment{id: cid4} = TestRepo.insert!(%Comment{text: "3", post_id: p2.id})

    assert %Ecto.Association.NotLoaded{} = p1.comments

    [p3, p1, p2] = TestRepo.preload([p3, p1, p2], :comments)
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

    [p3, p1, p2] = TestRepo.preload([p3, p1, p2], :permalink)
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

    [pl3, pl1, pl2] = TestRepo.preload([pl3, pl1, pl2], :post)
    assert %Post{id: ^pid1} = pl1.post
    refute pl2.post
    assert %Post{id: ^pid3} = pl3.post
  end

  test "preload belongs_to with shared assocs" do
    %Post{id: pid1} = TestRepo.insert!(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert!(%Post{title: "2"})

    c1 = TestRepo.insert!(%Comment{text: "1", post_id: pid1})
    c2 = TestRepo.insert!(%Comment{text: "2", post_id: pid1})
    c3 = TestRepo.insert!(%Comment{text: "3", post_id: pid2})

    [c3, c1, c2] = TestRepo.preload([c3, c1, c2], :post)
    assert %Post{id: ^pid1} = c1.post
    assert %Post{id: ^pid1} = c2.post
    assert %Post{id: ^pid2} = c3.post
  end

  test "preload many_to_many" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    p3 = TestRepo.insert!(%Post{title: "3"})

    # We use the same name to expose bugs in preload sorting
    %User{id: uid1} = TestRepo.insert!(%User{name: "1"})
    %User{id: uid3} = TestRepo.insert!(%User{name: "2"})
    %User{id: uid2} = TestRepo.insert!(%User{name: "2"})
    %User{id: uid4} = TestRepo.insert!(%User{name: "3"})

    TestRepo.insert_all "posts_users", [[post_id: p1.id, user_id: uid1],
                                        [post_id: p1.id, user_id: uid2],
                                        [post_id: p2.id, user_id: uid3],
                                        [post_id: p2.id, user_id: uid4],
                                        [post_id: p3.id, user_id: uid1],
                                        [post_id: p3.id, user_id: uid4]]

    assert %Ecto.Association.NotLoaded{} = p1.users

    [p1, p2, p3] = TestRepo.preload([p1, p2, p3], :users)
    assert [%User{id: ^uid1}, %User{id: ^uid2}] = p1.users |> sort_by_id
    assert [%User{id: ^uid3}, %User{id: ^uid4}] = p2.users |> sort_by_id
    assert [%User{id: ^uid1}, %User{id: ^uid4}] = p3.users |> sort_by_id
  end

  test "preload has_many through" do
    %Post{id: pid1} = p1 = TestRepo.insert!(%Post{})
    %Post{id: pid2} = p2 = TestRepo.insert!(%Post{})

    %User{id: uid1} = TestRepo.insert!(%User{name: "foo"})
    %User{id: uid2} = TestRepo.insert!(%User{name: "bar"})

    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid2})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid2, author_id: uid2})

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

  test "preload through with nil association" do
    %Comment{} = c = TestRepo.insert!(%Comment{post_id: nil})

    c = TestRepo.preload(c, [:post, :post_permalink])
    assert c.post == nil
    assert c.post_permalink == nil

    c = TestRepo.preload(c, [:post, :post_permalink])
    assert c.post == nil
    assert c.post_permalink == nil
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

  test "preload has_many through many_to_many" do
    %Post{} = p1 = TestRepo.insert!(%Post{})
    %Post{} = p2 = TestRepo.insert!(%Post{})

    %User{id: uid1} = TestRepo.insert!(%User{name: "foo"})
    %User{id: uid2} = TestRepo.insert!(%User{name: "bar"})

    TestRepo.insert_all "posts_users", [[post_id: p1.id, user_id: uid1],
                                        [post_id: p1.id, user_id: uid2],
                                        [post_id: p2.id, user_id: uid2]]

    %Comment{id: cid1} = TestRepo.insert!(%Comment{author_id: uid1})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{author_id: uid1})
    %Comment{id: cid3} = TestRepo.insert!(%Comment{author_id: uid2})
    %Comment{id: cid4} = TestRepo.insert!(%Comment{author_id: uid2})

    [p1, p2] = TestRepo.preload([p1, p2], :users_comments)

    # Through was preloaded
    [c1, c2, c3, c4] = p1.users_comments |> sort_by_id
    assert c1.id == cid1
    assert c2.id == cid2
    assert c3.id == cid3
    assert c4.id == cid4

    [c3, c4] = p2.users_comments |> sort_by_id
    assert c3.id == cid3
    assert c4.id == cid4

    # But we also preloaded everything along the way
    assert [u1, u2] = p1.users |> sort_by_id
    assert u1.id == uid1
    assert u2.id == uid2

    assert [u2] = p2.users
    assert u2.id == uid2
  end

  ## Empties

  test "preload empty" do
    assert TestRepo.preload([], :anything_goes) == []
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

  test "preload many_to_many with no associated entries" do
    p = TestRepo.insert!(%Post{title: "1"})
    p = TestRepo.preload(p, :users)

    assert p.title == "1"
    assert p.users == []
  end

  ## With queries

  test "preload with function" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    p3 = TestRepo.insert!(%Post{title: "3"})

    # We use the same text to expose bugs in preload sorting
    %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid3} = TestRepo.insert!(%Comment{text: "2", post_id: p2.id})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: p1.id})
    %Comment{id: cid4} = TestRepo.insert!(%Comment{text: "3", post_id: p2.id})

    assert [pe3, pe1, pe2] = TestRepo.preload([p3, p1, p2],
                                              comments: fn _ -> TestRepo.all(Comment) end)
    assert [%Comment{id: ^cid1}, %Comment{id: ^cid2}] = pe1.comments
    assert [%Comment{id: ^cid3}, %Comment{id: ^cid4}] = pe2.comments
    assert [] = pe3.comments
  end

  test "preload with query" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    p3 = TestRepo.insert!(%Post{title: "3"})

    # We use the same text to expose bugs in preload sorting
    %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid3} = TestRepo.insert!(%Comment{text: "2", post_id: p2.id})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: p1.id})
    %Comment{id: cid4} = TestRepo.insert!(%Comment{text: "3", post_id: p2.id})

    assert %Ecto.Association.NotLoaded{} = p1.comments

    # With empty query
    assert [pe3, pe1, pe2] = TestRepo.preload([p3, p1, p2],
                                              comments: from(c in Comment, where: false))
    assert [] = pe1.comments
    assert [] = pe2.comments
    assert [] = pe3.comments

    # With custom select
    assert [pe3, pe1, pe2] = TestRepo.preload([p3, p1, p2],
                                              comments: from(c in Comment, select: c.id))
    assert [^cid1, ^cid2] = pe1.comments
    assert [^cid3, ^cid4] = pe2.comments
    assert [] = pe3.comments

    # With custom ordered query
    assert [pe3, pe1, pe2] = TestRepo.preload([p3, p1, p2],
                                              comments: from(c in Comment, order_by: [desc: c.text]))
    assert [%Comment{id: ^cid2}, %Comment{id: ^cid1}] = pe1.comments
    assert [%Comment{id: ^cid4}, %Comment{id: ^cid3}] = pe2.comments
    assert [] = pe3.comments

    # With custom ordered query with preload
    assert [pe3, pe1, pe2] = TestRepo.preload([p3, p1, p2],
                                              comments: {from(c in Comment, order_by: [desc: c.text]), :post})
    assert [%Comment{id: ^cid2} = c2, %Comment{id: ^cid1} = c1] = pe1.comments
    assert [%Comment{id: ^cid4} = c4, %Comment{id: ^cid3} = c3] = pe2.comments
    assert [] = pe3.comments

    assert c1.post.title == "1"
    assert c2.post.title == "1"
    assert c3.post.title == "2"
    assert c4.post.title == "2"
  end

  test "preload through with query" do
    %Post{id: pid1} = p1 = TestRepo.insert!(%Post{})

    u1 = TestRepo.insert!(%User{name: "foo"})
    u2 = TestRepo.insert!(%User{name: "bar"})
    u3 = TestRepo.insert!(%User{name: "baz"})
    u4 = TestRepo.insert!(%User{name: "norf"})

    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: u1.id})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: u1.id})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: u2.id})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: u3.id})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: u4.id})

    np1 = TestRepo.preload(p1, comments_authors: from(u in User, where: u.name == "foo"))
    assert np1.comments_authors == [u1]

    assert_raise ArgumentError, ~r/Ecto expected a map\/struct with the key `id` but got: \d+/, fn ->
      TestRepo.preload(p1, comments_authors: from(u in User, order_by: u.name, select: u.id))
    end

    # The subpreload order does not matter because the result is dictated by comments
    np1 = TestRepo.preload(p1, comments_authors: from(u in User, order_by: u.name, select: %{id: u.id}))
    assert np1.comments_authors ==
           [%{id: u1.id}, %{id: u2.id}, %{id: u3.id}, %{id: u4.id}]
  end

  ## With take

  test "preload with take" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    _p = TestRepo.insert!(%Post{title: "3"})

    %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid3} = TestRepo.insert!(%Comment{text: "2", post_id: p2.id})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: p1.id})
    %Comment{id: cid4} = TestRepo.insert!(%Comment{text: "3", post_id: p2.id})

    assert %Ecto.Association.NotLoaded{} = p1.comments

    posts = TestRepo.all(from Post, preload: [:comments], select: [:id, comments: [:id, :post_id]])
    [p1, p2, p3] = sort_by_id(posts)
    assert p1.title == nil
    assert p2.title == nil
    assert p3.title == nil

    assert [%{id: ^cid1, text: nil}, %{id: ^cid2, text: nil}] = sort_by_id(p1.comments)
    assert [%{id: ^cid3, text: nil}, %{id: ^cid4, text: nil}] = sort_by_id(p2.comments)
    assert [] = sort_by_id(p3.comments)
  end

  test "preload through with take" do
    %Post{id: pid1} = TestRepo.insert!(%Post{})

    %User{id: uid1} = TestRepo.insert!(%User{name: "foo"})
    %User{id: uid2} = TestRepo.insert!(%User{name: "bar"})

    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert!(%Comment{post_id: pid1, author_id: uid2})

    [p1] = TestRepo.all from Post, preload: [:comments_authors], select: [:id, comments_authors: :id]
    [%{id: ^uid1, name: nil}, %{id: ^uid2, name: nil}] = p1.comments_authors |> sort_by_id
  end

  ## Nested

  test "preload many assocs" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})

    assert [p2, p1] = TestRepo.preload([p2, p1], [:comments, :users])
    assert p1.comments == []
    assert p2.comments == []
    assert p1.users == []
    assert p2.users == []
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

  ## Others

  @tag :invalid_prefix
  test "preload custom prefix from schema" do
    p = TestRepo.insert!(%Post{title: "1"})
    p = Ecto.put_meta(p, prefix: "this_surely_does_not_exist")
    # This preload should fail because it points to a prefix that does not exist
    assert catch_error(TestRepo.preload(p, [:comments]))
  end

  @tag :invalid_prefix
  test "preload custom prefix from options" do
    p = TestRepo.insert!(%Post{title: "1"})
    # This preload should fail because it points to a prefix that does not exist
    assert catch_error(TestRepo.preload(p, [:comments], prefix: "this_surely_does_not_exist"))
  end

  test "preload with binary_id" do
    c = TestRepo.insert!(%Custom{})
    u = TestRepo.insert!(%User{custom_id: c.bid})

    u = TestRepo.preload(u, :custom)
    assert u.custom.bid == c.bid
  end

  test "preload skips with association set but without id" do
    c1 = TestRepo.insert!(%Comment{text: "1"})
    u1 = TestRepo.insert!(%User{name: "name"})
    p1 = TestRepo.insert!(%Post{title: "title"})

    c1 = %{c1 | author: u1, author_id: nil, post: p1, post_id: nil}

    c1 = TestRepo.preload(c1, [:author, :post])
    assert c1.author == u1
    assert c1.post == p1
  end

  test "preload skips already loaded for cardinality one" do
    %Post{id: pid} = TestRepo.insert!(%Post{title: "1"})

    c1 = %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: pid})
    c2 = %Comment{id: _cid} = TestRepo.insert!(%Comment{text: "2", post_id: nil})

    [c1, c2] = TestRepo.preload([c1, c2], :post)
    assert %Post{id: ^pid} = c1.post
    assert c2.post == nil

    [c1, c2] = TestRepo.preload([c1, c2], post: :comments)
    assert [%Comment{id: ^cid1}] = c1.post.comments

    TestRepo.update_all Post, set: [title: "0"]
    TestRepo.update_all Comment, set: [post_id: pid]

    # Preloading once again shouldn't change the result
    [c1, c2] = TestRepo.preload([c1, c2], :post)
    assert %Post{id: ^pid, title: "1", comments: [_|_]} = c1.post
    assert c2.post == nil

    [c1, c2] = TestRepo.preload([c1, %{c2 | post_id: pid}], :post, force: true)
    assert %Post{id: ^pid, title: "0", comments: %Ecto.Association.NotLoaded{}} = c1.post
    assert %Post{id: ^pid, title: "0", comments: %Ecto.Association.NotLoaded{}} = c2.post
  end

  test "preload skips already loaded for cardinality many" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})

    %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: p2.id})

    [p1, p2] = TestRepo.preload([p1, p2], :comments)
    assert [%Comment{id: ^cid1}] = p1.comments
    assert [%Comment{id: ^cid2}] = p2.comments

    [p1, p2] = TestRepo.preload([p1, p2], comments: :post)
    assert hd(p1.comments).post.id == p1.id
    assert hd(p2.comments).post.id == p2.id

    TestRepo.update_all Comment, set: [text: "0"]

    # Preloading once again shouldn't change the result
    [p1, p2] = TestRepo.preload([p1, p2], :comments)
    assert [%Comment{id: ^cid1, text: "1", post: %Post{}}] = p1.comments
    assert [%Comment{id: ^cid2, text: "2", post: %Post{}}] = p2.comments

    [p1, p2] = TestRepo.preload([p1, p2], :comments, force: true)
    assert [%Comment{id: ^cid1, text: "0", post: %Ecto.Association.NotLoaded{}}] = p1.comments
    assert [%Comment{id: ^cid2, text: "0", post: %Ecto.Association.NotLoaded{}}] = p2.comments
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

    assert [p1, p2, p3] = TestRepo.all(query) |> sort_by_id
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
    [p1, p2, p3] = Enum.map(posts, fn {0, [p], 1, 2} -> p end) |> sort_by_id

    assert [%Comment{id: ^cid1}, %Comment{id: ^cid2}] = p1.comments |> sort_by_id
    assert [%Comment{id: ^cid3}, %Comment{id: ^cid4}] = p2.comments |> sort_by_id
    assert [] = p3.comments
  end

  defp sort_by_id(values) do
    Enum.sort_by(values, &(&1.id))
  end
end
