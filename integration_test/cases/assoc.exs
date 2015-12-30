Code.require_file "../support/types.exs", __DIR__

defmodule Ecto.Integration.AssocTest do
  use Ecto.Integration.Case

  alias Ecto.Integration.TestRepo
  import Ecto.Query

  alias Ecto.Integration.Post
  alias Ecto.Integration.User
  alias Ecto.Integration.Comment
  alias Ecto.Integration.Permalink

  test "has_many assoc" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "1"})

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

  test "many_to_many assoc" do
    p1 = TestRepo.insert!(%Post{title: "1", text: "hi"})
    p2 = TestRepo.insert!(%Post{title: "2", text: "ola"})
    p3 = TestRepo.insert!(%Post{title: "3", text: "hello"})

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

  test "has_one changeset assoc" do
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

    # Replacing with nil (on_replace: :nilify)
    changeset =
      post
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:permalink, nil)
    post = TestRepo.update!(changeset)
    refute post.permalink
    post = TestRepo.get!(from(Post, preload: [:permalink]), post.id)
    refute post.permalink

    assert [3] == TestRepo.all(from(p in Permalink, select: count(p.id)))
  end

  test "has_many changeset assoc" do
    c1 = %Comment{text: "1"}
    c2 = %Comment{text: "2"}

    # Inserting
    changeset =
      %Post{title: "1"}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:comments, [c1])
    post = TestRepo.insert!(changeset)
    [c1] = post.comments
    assert c1.id
    assert c1.post_id == post.id
    post = TestRepo.get!(from(Post, preload: [:comments]), post.id)
    [c1] = post.comments
    assert c1.text == "1"

    # Updating
    changeset =
      post
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:comments, [Ecto.Changeset.change(c1), Ecto.Changeset.change(c2)])
    post = TestRepo.update!(changeset)
    [_c1, c2] = post.comments |> Enum.sort_by(&(&1.id))
    assert c2.id
    assert c2.post_id == post.id
    post = TestRepo.get!(from(Post, preload: [:comments]), post.id)
    [c1, c2] = post.comments |> Enum.sort_by(&(&1.id))
    assert c1.text == "1"
    assert c2.text == "2"

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
      %{"uuid": u, "title": "fresh"}
    end

    # This will only work if we delete before performing inserts
    changeset =
      author
      |> Ecto.Changeset.cast(%{"posts" => posts_params}, ~w(), ~w())
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

  test "inserting with associations in structs" do
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
    p1 = TestRepo.insert!(%Post{title: "1", text: "hi"})
    p2 = TestRepo.insert!(%Post{title: "2", text: "hello"})

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
