defmodule Ecto.Integration.AssocTest do
  use Ecto.Integration.Case, async: Application.compile_env(:ecto, :async_integration_tests, true)

  alias Ecto.Integration.TestRepo
  import Ecto.Query

  alias Ecto.Integration.Custom
  alias Ecto.Integration.Post
  alias Ecto.Integration.User
  alias Ecto.Integration.PostUser
  alias Ecto.Integration.Comment
  alias Ecto.Integration.Permalink

  test "has_many assoc" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})

    %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: p1.id})
    %Comment{id: cid3} = TestRepo.insert!(%Comment{text: "3", post_id: p2.id})

    [c1, c2] = TestRepo.all Ecto.assoc(p1, :comments)
    assert c1.id == cid1
    assert c2.id == cid2

    [c1, c2, c3] = TestRepo.all Ecto.assoc([p1, p2], :comments)
    assert c1.id == cid1
    assert c2.id == cid2
    assert c3.id == cid3
  end

  test "has_one assoc" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})

    %Permalink{id: lid1} = TestRepo.insert!(%Permalink{url: "1", post_id: p1.id})
    %Permalink{}         = TestRepo.insert!(%Permalink{url: "2"})
    %Permalink{id: lid3} = TestRepo.insert!(%Permalink{url: "3", post_id: p2.id})

    [l1, l3] = TestRepo.all Ecto.assoc([p1, p2], :permalink)
    assert l1.id == lid1
    assert l3.id == lid3
  end

  test "belongs_to assoc" do
    %Post{id: pid1} = TestRepo.insert!(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert!(%Post{title: "2"})

    l1 = TestRepo.insert!(%Permalink{url: "1", post_id: pid1})
    l2 = TestRepo.insert!(%Permalink{url: "2"})
    l3 = TestRepo.insert!(%Permalink{url: "3", post_id: pid2})

    assert [p1, p2] = TestRepo.all Ecto.assoc([l1, l2, l3], :post)
    assert p1.id == pid1
    assert p2.id == pid2
  end

  test "has_many through assoc" do
    p1 = TestRepo.insert!(%Post{})
    p2 = TestRepo.insert!(%Post{})

    u1 = TestRepo.insert!(%User{name: "zzz"})
    u2 = TestRepo.insert!(%User{name: "aaa"})

    %Comment{} = TestRepo.insert!(%Comment{post_id: p1.id, author_id: u1.id})
    %Comment{} = TestRepo.insert!(%Comment{post_id: p1.id, author_id: u1.id})
    %Comment{} = TestRepo.insert!(%Comment{post_id: p1.id, author_id: u2.id})
    %Comment{} = TestRepo.insert!(%Comment{post_id: p2.id, author_id: u2.id})

    query = Ecto.assoc([p1, p2], :comments_authors) |> order_by([a], a.name)
    assert [^u2, ^u1] = TestRepo.all(query)

    # Dynamic through
    query = Ecto.assoc([p1, p2], [:comments, :author]) |> order_by([a], a.name)
    assert [^u2, ^u1] = TestRepo.all(query)
  end

  @tag :on_replace_nilify
  test "has_many through-through assoc leading" do
    p1 = TestRepo.insert!(%Post{})
    p2 = TestRepo.insert!(%Post{})

    u1 = TestRepo.insert!(%User{})
    u2 = TestRepo.insert!(%User{})

    pl1 = TestRepo.insert!(%Permalink{user_id: u1.id, url: "zzz"})
    pl2 = TestRepo.insert!(%Permalink{user_id: u2.id, url: "aaa"})

    %Comment{} = TestRepo.insert!(%Comment{post_id: p1.id, author_id: u1.id})
    %Comment{} = TestRepo.insert!(%Comment{post_id: p1.id, author_id: u1.id})
    %Comment{} = TestRepo.insert!(%Comment{post_id: p1.id, author_id: u2.id})
    %Comment{} = TestRepo.insert!(%Comment{post_id: p2.id, author_id: u2.id})

    query = Ecto.assoc([p1, p2], :comments_authors_permalinks) |> order_by([p], p.url)
    assert [^pl2, ^pl1] = TestRepo.all(query)

    # Dynamic through
    query = Ecto.assoc([p1, p2], [:comments, :author, :permalink]) |> order_by([p], p.url)
    assert [^pl2, ^pl1] = TestRepo.all(query)
  end

  test "has_many through-through assoc trailing" do
    p1  = TestRepo.insert!(%Post{})
    u1  = TestRepo.insert!(%User{})
    pl1 = TestRepo.insert!(%Permalink{user_id: u1.id, post_id: p1.id})

    %Comment{} = TestRepo.insert!(%Comment{post_id: p1.id, author_id: u1.id})

    query = Ecto.assoc([pl1], :post_comments_authors)
    assert [^u1] = TestRepo.all(query)

    # Dynamic through
    query = Ecto.assoc([pl1], [:post, :comments, :author])
    assert [^u1] = TestRepo.all(query)
  end

  test "has_many through has_many, many_to_many and has_many" do
    user1 = %User{id: uid1} = TestRepo.insert!(%User{name: "Gabriel"})
    %User{id: uid2} = TestRepo.insert!(%User{name: "Isadora"})
    %User{id: uid3} = TestRepo.insert!(%User{name: "Joey Mush"})

    p1 = TestRepo.insert!(%Post{title: "p1", author_id: uid1})
    p2 = TestRepo.insert!(%Post{title: "p2", author_id: uid2})
    p3 = TestRepo.insert!(%Post{title: "p3", author_id: uid2})
    TestRepo.insert!(%Post{title: "p4", author_id: uid3})

    TestRepo.insert_all "posts_users", [[post_id: p1.id, user_id: uid1],
                                        [post_id: p1.id, user_id: uid2],
                                        [post_id: p2.id, user_id: uid3]]

    [pid1, pid2, pid3] =
      Ecto.assoc(user1, :related_2nd_order_posts)
      |> TestRepo.all()
      |> Enum.map(fn %Post{id: id} -> id end)
      |> Enum.sort()

    assert p1.id == pid1
    assert p2.id == pid2
    assert p3.id == pid3
  end

  test "has_many through has_many, belongs_to and a nested has through" do
    user1 = TestRepo.insert!(%User{name: "Gabriel"})
    user2 = TestRepo.insert!(%User{name: "Isadora"})
    user3 = TestRepo.insert!(%User{name: "Joey"})

    post1 = TestRepo.insert!(%Post{title: "p1"})
    post2 = TestRepo.insert!(%Post{title: "p2"})

    TestRepo.insert!(%Comment{author_id: user1.id, text: "c1", post_id: post1.id})
    TestRepo.insert!(%Comment{author_id: user2.id, text: "c2", post_id: post1.id})
    TestRepo.insert!(%Comment{author_id: user3.id, text: "c3", post_id: post2.id})

    [u1_id, u2_id] =
      Ecto.assoc(user1, :co_commenters)
      |> TestRepo.all()
      |> Enum.map(fn %User{id: id} -> id end)
      |> Enum.sort()

    assert u1_id == user1.id
    assert u2_id == user2.id
  end

  test "has_many through two many_to_many associations" do
    user1 = %User{id: uid1} = TestRepo.insert!(%User{name: "Gabriel"})
    %User{id: uid2} = TestRepo.insert!(%User{name: "Isadora"})
    %User{id: uid3} = TestRepo.insert!(%User{name: "Joey Mush"})

    p1 = TestRepo.insert!(%Post{title: "p1", author_id: uid1})
    TestRepo.insert!(%Post{title: "p2", author_id: uid2})
    p3 = TestRepo.insert!(%Post{title: "p3", author_id: uid2})
    p4 = TestRepo.insert!(%Post{title: "p4", author_id: uid3})

    TestRepo.insert_all "posts_users", [[post_id: p3.id, user_id: uid1],
                                        [post_id: p3.id, user_id: uid2],
                                        [post_id: p1.id, user_id: uid3]]

    TestRepo.insert!(%PostUser{post_id: p1.id, user_id: uid2})
    TestRepo.insert!(%PostUser{post_id: p3.id, user_id: uid1})
    TestRepo.insert!(%PostUser{post_id: p3.id, user_id: uid2})
    TestRepo.insert!(%PostUser{post_id: p4.id, user_id: uid3})

    [u1, u2] =
      Ecto.assoc(user1, :users_through_schema_posts)
      |> TestRepo.all()
      |> Enum.map(fn %User{id: id} -> id end)
      |> Enum.sort()

    assert uid1 == u1
    assert uid2 == u2
  end

  test "has_many through with where" do
    post1 = TestRepo.insert!(%Post{title: "p1"})
    post2 = TestRepo.insert!(%Post{title: "p2"})
    post3 = TestRepo.insert!(%Post{title: "p3"})

    author = TestRepo.insert!(%User{name: "john"})

    TestRepo.insert!(%Comment{text: "1", lock_version: 1, post_id: post1.id, author_id: author.id})
    TestRepo.insert!(%Comment{text: "2", lock_version: 2, post_id: post2.id, author_id: author.id})
    TestRepo.insert!(%Comment{text: "3", lock_version: 2, post_id: post3.id, author_id: author.id})

    [p2, p3] = Ecto.assoc(author, :v2_comments_posts) |> TestRepo.all() |> Enum.sort_by(&(&1.id))
    assert p2.id == post2.id
    assert p3.id == post3.id
  end

  test "many_to_many assoc" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "2"})
    p3 = TestRepo.insert!(%Post{title: "3"})

    %User{id: uid1} = TestRepo.insert!(%User{name: "john"})
    %User{id: uid2} = TestRepo.insert!(%User{name: "mary"})

    TestRepo.insert_all "posts_users", [[post_id: p1.id, user_id: uid1],
                                        [post_id: p1.id, user_id: uid2],
                                        [post_id: p2.id, user_id: uid2]]

    [u1, u2] = TestRepo.all Ecto.assoc([p1], :users)
    assert u1.id == uid1
    assert u2.id == uid2

    [u2] = TestRepo.all Ecto.assoc([p2], :users)
    assert u2.id == uid2
    [] = TestRepo.all Ecto.assoc([p3], :users)

    [u1, u2, u2] = TestRepo.all Ecto.assoc([p1, p2, p3], :users)
    assert u1.id == uid1
    assert u2.id == uid2
  end

  ## Changesets

  test "has_one changeset assoc (on_replace: :delete)" do
    # Insert new
    changeset =
      %Post{title: "1"}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:permalink, %Permalink{url: "1"})
    post = TestRepo.insert!(changeset)
    assert post.permalink.id
    assert post.permalink.post_id == post.id
    assert post.permalink.url == "1"
    post = TestRepo.get!(from(Post, preload: [:permalink]), post.id)
    assert post.permalink.url == "1"

    # Replace with new
    changeset =
      post
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:permalink, %Permalink{url: "2"})
    post = TestRepo.update!(changeset)
    assert post.permalink.id
    assert post.permalink.post_id == post.id
    assert post.permalink.url == "2"
    post = TestRepo.get!(from(Post, preload: [:permalink]), post.id)
    assert post.permalink.url == "2"

    # Replacing with existing
    existing = TestRepo.insert!(%Permalink{url: "3"})
    changeset =
      post
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:permalink, existing)
    post = TestRepo.update!(changeset)
    assert post.permalink.id
    assert post.permalink.post_id == post.id
    assert post.permalink.url == "3"
    post = TestRepo.get!(from(Post, preload: [:permalink]), post.id)
    assert post.permalink.url == "3"

    # Replacing with nil (on_replace: :delete)
    changeset =
      post
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:permalink, nil)
    post = TestRepo.update!(changeset)
    refute post.permalink
    post = TestRepo.get!(from(Post, preload: [:permalink]), post.id)
    refute post.permalink

    assert [0] == TestRepo.all(from(p in Permalink, select: count(p.id)))
  end

  test "has_one changeset assoc (on_replace: :delete_if_exists)" do
    permalink = TestRepo.insert!(%Permalink{url: "1"})
    post = TestRepo.insert!(%Post{title: "1", permalink: permalink, force_permalink: permalink})
    TestRepo.delete!(permalink)

    assert_raise Ecto.StaleEntryError, fn ->
      post
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:permalink, nil)
      |> TestRepo.update!()
    end

    post =
      post
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:force_permalink, nil)
      |> TestRepo.update!()

    assert post.force_permalink == nil
  end

  @tag :on_replace_nilify
  test "has_one changeset assoc (on_replace: :nilify)" do
    # Insert new
    changeset =
      %User{name: "1"}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:permalink, %Permalink{url: "1"})
    user = TestRepo.insert!(changeset)
    assert user.permalink.id
    assert user.permalink.user_id == user.id
    assert user.permalink.url == "1"
    user = TestRepo.get!(from(User, preload: [:permalink]), user.id)
    assert user.permalink.url == "1"

    # Replace with new
    changeset =
      user
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:permalink, %Permalink{url: "2"})
    user = TestRepo.update!(changeset)
    assert user.permalink.id
    assert user.permalink.user_id == user.id
    assert user.permalink.url == "2"
    user = TestRepo.get!(from(User, preload: [:permalink]), user.id)
    assert user.permalink.url == "2"

    # Replacing with nil (on_replace: :nilify)
    changeset =
      user
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:permalink, nil)
    user = TestRepo.update!(changeset)
    refute user.permalink
    user = TestRepo.get!(from(User, preload: [:permalink]), user.id)
    refute user.permalink

    assert [2] == TestRepo.all(from(p in Permalink, select: count(p.id)))
  end

  @tag :on_replace_update
  test "has_one changeset assoc (on_replace: :update)" do
    # Insert new
    changeset =
      %Post{title: "1"}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:update_permalink, %Permalink{url: "1"})
    post = TestRepo.insert!(changeset)
    assert post.update_permalink.id
    assert post.update_permalink.post_id == post.id
    assert post.update_permalink.url == "1"
    post = TestRepo.get!(from(Post, preload: [:update_permalink]), post.id)
    assert post.update_permalink.url == "1"

    perma = post.update_permalink

    # Put on update
    changeset =
      post
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:update_permalink, %{url: "2"})
    post = TestRepo.update!(changeset)
    assert post.update_permalink.id == perma.id
    assert post.update_permalink.post_id == post.id
    assert post.update_permalink.url == "2"
    post = TestRepo.get!(from(Post, preload: [:update_permalink]), post.id)
    assert post.update_permalink.url == "2"

    # Cast on update
    changeset =
      post
      |> Ecto.Changeset.cast(%{update_permalink: %{url: "3"}}, [])
      |> Ecto.Changeset.cast_assoc(:update_permalink)
    post = TestRepo.update!(changeset)
    assert post.update_permalink.id == perma.id
    assert post.update_permalink.post_id == post.id
    assert post.update_permalink.url == "3"
    post = TestRepo.get!(from(Post, preload: [:update_permalink]), post.id)
    assert post.update_permalink.url == "3"

    # Replace with new struct
    assert_raise RuntimeError, ~r"you are only allowed\sto update the existing entry", fn ->
      post
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:update_permalink, %Permalink{url: "4"})
    end

    # Replace with existing struct
    assert_raise RuntimeError, ~r"you are only allowed\sto update the existing entry", fn ->
      post
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:update_permalink, TestRepo.insert!(%Permalink{url: "5"}))
    end

    # Replacing with nil (on_replace: :update)
    changeset =
      post
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:update_permalink, nil)
    post = TestRepo.update!(changeset)
    refute post.update_permalink
    post = TestRepo.get!(from(Post, preload: [:update_permalink]), post.id)
    refute post.update_permalink

    assert [2] == TestRepo.all(from(p in Permalink, select: count(p.id)))
  end

  test "has_many changeset assoc (on_replace: :delete)" do
    c1 = TestRepo.insert! %Comment{text: "1"}
    c2 = %Comment{text: "2"}

    # Inserting
    changeset =
      %Post{title: "1"}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:comments, [c2])
    post = TestRepo.insert!(changeset)
    [c2] = post.comments
    assert c2.id
    assert c2.post_id == post.id
    post = TestRepo.get!(from(Post, preload: [:comments]), post.id)
    [c2] = post.comments
    assert c2.text == "2"

    # Updating
    changeset =
      post
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:comments, [Ecto.Changeset.change(c1, text: "11"),
                                              Ecto.Changeset.change(c2, text: "22")])
    post = TestRepo.update!(changeset)
    [c1, _c2] = post.comments |> Enum.sort_by(&(&1.id))
    assert c1.id
    assert c1.post_id == post.id
    post = TestRepo.get!(from(Post, preload: [:comments]), post.id)
    [c1, c2] = post.comments |> Enum.sort_by(&(&1.id))
    assert c1.text == "11"
    assert c2.text == "22"

    # Replacing (on_replace: :delete)
    changeset =
      post
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:comments, [])
    post = TestRepo.update!(changeset)
    assert post.comments == []
    post = TestRepo.get!(from(Post, preload: [:comments]), post.id)
    assert post.comments == []

    assert [0] == TestRepo.all(from(c in Comment, select: count(c.id)))
  end

  test "has_many changeset assoc (on_replace: :delete_if_exists)" do
    comment = TestRepo.insert!(%Comment{text: "1"})
    post = TestRepo.insert!(%Post{title: "1", comments: [comment], force_comments: [comment]})

    TestRepo.delete!(comment)

    assert_raise Ecto.StaleEntryError, fn ->
      post
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:comments, [])
      |> TestRepo.update!()
    end

    post =
      post
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:force_comments, [])
      |> TestRepo.update!()

    assert post.force_comments == []
  end

  test "has_many changeset assoc (on_replace: :nilify)" do
    c1 = TestRepo.insert! %Comment{text: "1"}
    c2 = %Comment{text: "2"}

    # Inserting
    changeset =
      %User{name: "1"}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:comments, [c1, c2])
    user = TestRepo.insert!(changeset)
    [c1, c2] = user.comments
    assert c1.id
    assert c1.author_id == user.id
    assert c2.id
    assert c2.author_id == user.id
    user = TestRepo.get!(from(User, preload: [:comments]), user.id)
    [c1, c2] = user.comments
    assert c1.text == "1"
    assert c2.text == "2"

    # Replacing (on_replace: :nilify)
    changeset =
      user
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:comments, [])
    user = TestRepo.update!(changeset)
    assert user.comments == []
    user = TestRepo.get!(from(User, preload: [:comments]), user.id)
    assert user.comments == []

    assert [2] == TestRepo.all(from(c in Comment, select: count(c.id)))
  end

  test "many_to_many changeset assoc" do
    u1 = TestRepo.insert! %User{name: "1"}
    u2 = %User{name: "2"}

    # Inserting
    changeset =
      %Post{title: "1"}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:users, [u2])
    post = TestRepo.insert!(changeset)
    [u2] = post.users
    assert u2.id
    post = TestRepo.get!(from(Post, preload: [:users]), post.id)
    [u2] = post.users
    assert u2.name == "2"

    assert [1] == TestRepo.all(from(j in "posts_users", select: count(j.post_id)))

    # Updating
    changeset =
      post
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:users, [Ecto.Changeset.change(u1, name: "11"),
                                           Ecto.Changeset.change(u2, name: "22")])
    post = TestRepo.update!(changeset)
    [u1, _u2] = post.users |> Enum.sort_by(&(&1.id))
    assert u1.id
    post = TestRepo.get!(from(Post, preload: [:users]), post.id)
    [u1, u2] = post.users |> Enum.sort_by(&(&1.id))
    assert u1.name == "11"
    assert u2.name == "22"

    assert [2] == TestRepo.all(from(j in "posts_users", select: count(j.post_id)))

    # Replacing (on_replace: :delete)
    changeset =
      post
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:users, [])
    post = TestRepo.update!(changeset)
    assert post.users == []
    post = TestRepo.get!(from(Post, preload: [:users]), post.id)
    assert post.users == []

    assert [0] == TestRepo.all(from(j in "posts_users", select: count(j.post_id)))
    assert [2] == TestRepo.all(from(c in User, select: count(c.id)))
  end

  test "many_to_many changeset assoc with schema" do
    p1 = TestRepo.insert! %Post{title: "1"}
    p2 = %Post{title: "2"}

    # Inserting
    changeset =
      %User{name: "1"}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:schema_posts, [p2])
    user = TestRepo.insert!(changeset)
    [p2] = user.schema_posts
    assert p2.id
    user = TestRepo.get!(from(User, preload: [:schema_posts]), user.id)
    [p2] = user.schema_posts
    assert p2.title == "2"

    [up2] = TestRepo.all(PostUser) |> Enum.sort_by(&(&1.id))
    assert up2.post_id == p2.id
    assert up2.user_id == user.id
    assert up2.inserted_at
    assert up2.updated_at

    # Updating
    changeset =
      user
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:schema_posts, [Ecto.Changeset.change(p1, title: "11"),
                                                  Ecto.Changeset.change(p2, title: "22")])
    user = TestRepo.update!(changeset)
    [p1, _p2] = user.schema_posts |> Enum.sort_by(&(&1.id))
    assert p1.id
    user = TestRepo.get!(from(User, preload: [:schema_posts]), user.id)
    [p1, p2] = user.schema_posts |> Enum.sort_by(&(&1.id))
    assert p1.title == "11"
    assert p2.title == "22"

    [_up2, up1] = TestRepo.all(PostUser) |> Enum.sort_by(&(&1.id))
    assert up1.post_id == p1.id
    assert up1.user_id == user.id
    assert up1.inserted_at
    assert up1.updated_at
  end

  test "many_to_many changeset assoc with self-referential binary_id" do
    assoc_custom = TestRepo.insert!(%Custom{uuid: Ecto.UUID.generate()})
    custom = TestRepo.insert!(%Custom{customs: [assoc_custom]})

    custom = Custom |> TestRepo.get!(custom.bid) |> TestRepo.preload(:customs)
    assert [_] = custom.customs

    custom =
      custom
      |> Ecto.Changeset.change(%{})
      |> Ecto.Changeset.put_assoc(:customs, [])
      |> TestRepo.update!
    assert [] = custom.customs

    custom = Custom |> TestRepo.get!(custom.bid) |> TestRepo.preload(:customs)
    assert [] = custom.customs
  end

  @tag :unique_constraint
  test "has_many changeset assoc with constraints" do
    author = TestRepo.insert!(%User{name: "john doe"})
    p1 = TestRepo.insert!(%Post{title: "hello", author_id: author.id})
    TestRepo.insert!(%Post{title: "world", author_id: author.id})

    # Asserts that `unique_constraint` for `uuid` exists
    assert_raise Ecto.ConstraintError, fn ->
      TestRepo.insert!(%Post{title: "another", author_id: author.id, uuid: p1.uuid})
    end

    author = TestRepo.preload author, [:posts]
    posts_params = Enum.map author.posts, fn %Post{uuid: u} ->
      %{uuid: u, title: "fresh"}
    end

    # This will only work if we delete before performing inserts
    changeset =
      author
      |> Ecto.Changeset.cast(%{"posts" => posts_params}, ~w())
      |> Ecto.Changeset.cast_assoc(:posts)
    author = TestRepo.update! changeset
    assert Enum.map(author.posts, &(&1.title)) == ["fresh", "fresh"]
  end

  test "belongs_to changeset assoc" do
    # Insert new
    changeset =
      %Permalink{url: "1"}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:post, %Post{title: "1"})
    perma = TestRepo.insert!(changeset)
    post = perma.post
    assert perma.post_id
    assert perma.post_id == post.id
    assert perma.post.title == "1"

    # Replace with new
    changeset =
      perma
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:post, %Post{title: "2"})
    perma = TestRepo.update!(changeset)
    assert perma.post.id != post.id
    post = perma.post
    assert perma.post_id
    assert perma.post_id == post.id
    assert perma.post.title == "2"

    # Replace with existing
    existing = TestRepo.insert!(%Post{title: "3"})
    changeset =
      perma
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:post, existing)
    perma = TestRepo.update!(changeset)
    post = perma.post
    assert perma.post_id == post.id
    assert perma.post_id == existing.id
    assert perma.post.title == "3"

    # Replace with nil
    changeset =
      perma
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:post, nil)
    perma = TestRepo.update!(changeset)
    assert perma.post == nil
    assert perma.post_id == nil
  end

  test "belongs_to changeset assoc (on_replace: :update)" do
    # Insert new
    changeset =
      %Permalink{url: "1"}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:update_post, %Post{title: "1"})
    perma = TestRepo.insert!(changeset)
    post = perma.update_post
    assert perma.post_id
    assert perma.post_id == post.id
    assert perma.update_post.title == "1"

    # Casting on update
    changeset =
      perma
      |> Ecto.Changeset.cast(%{update_post: %{title: "2"}}, [])
      |> Ecto.Changeset.cast_assoc(:update_post)
    perma = TestRepo.update!(changeset)
    assert perma.update_post.id == post.id
    post = perma.update_post
    assert perma.post_id
    assert perma.post_id == post.id
    assert perma.update_post.title == "2"

    # Replace with nil
    changeset =
      perma
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:update_post, nil)
    perma = TestRepo.update!(changeset)
    assert perma.update_post == nil
    assert perma.post_id == nil
  end

  test "inserting struct with associations" do
    tree = %Permalink{
      url: "root",
      post: %Post{
        title: "belongs_to",
        comments: [
          %Comment{text: "child 1"},
          %Comment{text: "child 2"},
        ]
      }
    }

    tree = TestRepo.insert!(tree)
    assert tree.id
    assert tree.post.id
    assert length(tree.post.comments) == 2
    assert Enum.all?(tree.post.comments, & &1.id)

    tree = TestRepo.get!(from(Permalink, preload: [post: :comments]), tree.id)
    assert tree.id
    assert tree.post.id
    assert length(tree.post.comments) == 2
    assert Enum.all?(tree.post.comments, & &1.id)
  end

  test "inserting struct with empty associations" do
    permalink = TestRepo.insert!(%Permalink{url: "root", post: nil})
    assert permalink.post == nil

    post = TestRepo.insert!(%Post{title: "empty", comments: []})
    assert post.comments == []
  end

  test "inserting changeset with empty cast associations" do
    changeset =
      %Permalink{}
      |> Ecto.Changeset.cast(%{url: "root", post: nil}, [:url])
      |> Ecto.Changeset.cast_assoc(:post)
    permalink = TestRepo.insert!(changeset)
    assert permalink.post == nil

    changeset =
      %Post{}
      |> Ecto.Changeset.cast(%{title: "root", comments: []}, [:title])
      |> Ecto.Changeset.cast_assoc(:comments)
    post = TestRepo.insert!(changeset)
    assert post.comments == []
  end

  test "inserting changeset with empty put associations" do
    changeset =
      %Permalink{}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:post, nil)
    permalink = TestRepo.insert!(changeset)
    assert permalink.post == nil

    changeset =
      %Post{}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:comments, [])
    post = TestRepo.insert!(changeset)
    assert post.comments == []
  end

  test "updating changeset with empty cast associations" do
    post = TestRepo.insert!(%Post{})
    c1 = TestRepo.insert!(%Comment{post_id: post.id})
    c2 = TestRepo.insert!(%Comment{post_id: post.id})

    assert TestRepo.all(Comment) == [c1, c2]

    post = TestRepo.get!(from(Post, preload: [:comments]), post.id)

    post
    |> Ecto.Changeset.change
    |> Ecto.Changeset.put_assoc(:comments, [])
    |> TestRepo.update!()

    assert TestRepo.all(Comment) == []
  end

  ## Dependent

  test "has_many assoc on delete deletes all" do
    post = TestRepo.insert!(%Post{})
    TestRepo.insert!(%Comment{post_id: post.id})
    TestRepo.insert!(%Comment{post_id: post.id})
    TestRepo.delete!(post)

    assert TestRepo.all(Comment) == []
    refute Process.get(Comment)
  end

  test "has_many assoc on delete nilifies all" do
    user = TestRepo.insert!(%User{})
    TestRepo.insert!(%Comment{author_id: user.id})
    TestRepo.insert!(%Comment{author_id: user.id})
    TestRepo.delete!(user)

    author_ids = Comment |> TestRepo.all() |> Enum.map(fn(comment) -> comment.author_id end)

    assert author_ids == [nil, nil]
    refute Process.get(Comment)
  end

  test "has_many assoc on delete does nothing" do
    user = TestRepo.insert!(%User{})
    TestRepo.insert!(%Post{author_id: user.id})

    TestRepo.delete!(user)
    assert Enum.count(TestRepo.all(Post)) == 1
  end

  test "many_to_many assoc on delete deletes all" do
    p1 = TestRepo.insert!(%Post{title: "1", visits: 1})
    p2 = TestRepo.insert!(%Post{title: "2", visits: 2})

    u1 = TestRepo.insert!(%User{name: "john"})
    u2 = TestRepo.insert!(%User{name: "mary"})

    TestRepo.insert_all "posts_users", [[post_id: p1.id, user_id: u1.id],
                                        [post_id: p1.id, user_id: u1.id],
                                        [post_id: p2.id, user_id: u2.id]]
    TestRepo.delete!(p1)

    [pid2] = TestRepo.all from(p in Post, select: p.id)
    assert pid2 == p2.id

    [[pid2, uid2]] = TestRepo.all from(j in "posts_users", select: [j.post_id, j.user_id])
    assert pid2 == p2.id
    assert uid2 == u2.id

    [uid1, uid2] = TestRepo.all from(u in User, select: u.id)
    assert uid1 == u1.id
    assert uid2 == u2.id
  end
end
