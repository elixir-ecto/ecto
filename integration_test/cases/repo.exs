defmodule Ecto.Integration.RepoTest do
  use Ecto.Integration.Case

  require Ecto.Integration.TestRepo, as: TestRepo
  import Ecto.Query

  alias Ecto.Integration.Post
  alias Ecto.Integration.PostUsecTimestamps
  alias Ecto.Integration.Comment
  alias Ecto.Integration.Permalink
  alias Ecto.Integration.User
  alias Ecto.Integration.Custom
  alias Ecto.Integration.Barebone
  alias Ecto.Schema.Metadata

  test "returns already started for started repos" do
    assert {:error, {:already_started, _}} = TestRepo.start_link
  end

  test "fetch empty" do
    assert [] == TestRepo.all(Post)
    assert [] == TestRepo.all(from p in Post)
  end

  test "fetch with in" do
    TestRepo.insert(%Post{title: "hello"})

    assert []  = TestRepo.all from p in Post, where: p.title in []
    assert []  = TestRepo.all from p in Post, where: p.title in ["1", "2", "3"]
    assert []  = TestRepo.all from p in Post, where: p.title in ^[]

    assert [_] = TestRepo.all from p in Post, where: not p.title in []
    assert [_] = TestRepo.all from p in Post, where: p.title in ["1", "hello", "3"]
    assert [_] = TestRepo.all from p in Post, where: p.title in ["1", ^"hello", "3"]
    assert [_] = TestRepo.all from p in Post, where: p.title in ^["1", "hello", "3"]
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

    deleted_meta = %Metadata{state: :deleted, source: "posts"}
    assert %Post{} = to_be_deleted = TestRepo.insert(post)
    assert %Post{__meta__: ^deleted_meta} = TestRepo.delete(to_be_deleted)

    loaded_meta = %Metadata{state: :loaded, source: "posts"}
    assert %Post{__meta__: ^loaded_meta} = TestRepo.insert(post)

    post = TestRepo.one(Post)
    assert post.__meta__.state == :loaded
    assert post.inserted_at

    post = %{post | text: "coming very soon..."}
    post = put_in post.__meta__.state, :built
    assert %Post{__meta__: ^loaded_meta} = TestRepo.update(post)
  end

  test "insert and update with changeset" do
    # On insert we merge the fields and changes
    changeset = Ecto.Changeset.cast(%Post{text: "x", title: "wrong"},
                                    %{"title" => "hello", "temp" => "unknown"}, ~w(title temp), ~w())

    post = TestRepo.insert(changeset)
    assert %Post{text: "x", title: "hello", temp: "unknown"} = post
    assert %Post{text: "x", title: "hello", temp: "temp"} = TestRepo.get!(Post, post.id)

    # On update we merge only fields
    changeset = Ecto.Changeset.cast(%{post | text: "y"},
                                    %{"title" => "world", "temp" => "unknown"}, ~w(title temp), ~w())

    assert %Post{text: "y", title: "world", temp: "unknown"} = TestRepo.update(changeset)
    assert %Post{text: "x", title: "world", temp: "temp"} = TestRepo.get!(Post, post.id)
  end

  test "insert and update with empty changeset" do
    # On insert we merge the fields and changes
    changeset = Ecto.Changeset.cast(%Comment{}, %{}, ~w(), ~w())
    assert %Comment{} = comment = TestRepo.insert(changeset)

    # Assert we can update the same value twice,
    # without changes, without triggering stale errors.
    changeset = Ecto.Changeset.cast(comment, %{}, ~w(), ~w())
    assert ^comment = TestRepo.update(changeset)
    assert ^comment = TestRepo.update(changeset)
  end

  test "insert with no primary key" do
    assert %Barebone{num: nil} = TestRepo.insert(%Barebone{})
    assert %Barebone{num: 13} = TestRepo.insert(%Barebone{num: 13})
  end

  @tag :assigns_primary_key
  test "insert with user-assigned primary key" do
    assert %Post{id: 1} = TestRepo.insert(%Post{id: 1})
  end

  @tag :assigns_primary_key
  test "insert and update with user-assigned primary key in changeset" do
    changeset = Ecto.Changeset.cast(%Post{id: 11}, %{"id" => "13"}, ~w(id), ~w())
    assert %Post{id: 13} = post = TestRepo.insert(changeset)

    changeset = Ecto.Changeset.cast(post, %{"id" => "15"}, ~w(id), ~w())
    assert %Post{id: 15} = TestRepo.update(changeset)
  end

  @tag :read_after_writes
  test "insert and update with changeset read after writes" do
    changeset = Ecto.Changeset.cast(%Custom{uuid: "0123456789abcdef"}, %{}, ~w(), ~w())

    # There is no dirty tracking on insert, even with changesets,
    # so database defaults kick in only with nil read after writes.
    # counter should be 10, visits should be nil, even with same defaults.
    assert %Custom{uuid: cid, counter: 10, visits: nil} = custom = TestRepo.insert(changeset)

    # Make sure the values we see are actually the ones in the DB
    assert %Custom{uuid: cid, counter: 10, visits: nil} = TestRepo.get!(Custom, "0123456789abcdef")

    # Set the counter to 11 behind the scenes, it shall be read again
    TestRepo.update(%{custom | counter: 11})

    # Now a combination of dirty tracking with read_after_writes
    # allow us to see the new counter value.
    changeset = Ecto.Changeset.cast(custom, %{"visits" => "13"}, ~w(visits), ~w())
    assert %Custom{uuid: ^cid, counter: 11, visits: 13} = TestRepo.update(changeset)
  end

  test "validate_unique/3" do
    import Ecto.Changeset
    post = TestRepo.insert(%Post{title: "HELLO"})

    on_insert = cast(%Post{}, %{"title" => "HELLO"}, ~w(title), ~w())
    assert validate_unique(on_insert, :title, on: TestRepo).errors != []

    on_insert = cast(%Post{}, %{"title" => "hello"}, ~w(title), ~w())
    assert validate_unique(on_insert, :title, on: TestRepo, downcase: true).errors != []

    on_update = cast(post, %{"title" => "HELLO"}, ~w(title), ~w())
    assert validate_unique(on_update, :title, on: TestRepo).errors == []

    on_update = cast(post, %{"title" => nil}, ~w(), ~w(title))
    assert validate_unique(on_update, :title, on: TestRepo).errors == []

    on_update = cast(%{post | id: post.id + 1, title: nil}, %{"title" => "HELLO"}, ~w(title), ~w())
    assert validate_unique(on_update, :title, on: TestRepo).errors != []
  end

  @tag :case_sensitive
  test "validate_unique/3 case sensitive" do
    import Ecto.Changeset
    post = TestRepo.insert(%Post{title: "HELLO"})

    on_insert = cast(%Post{}, %{"title" => "hello"}, ~w(title), ~w())
    assert validate_unique(on_insert, :title, on: TestRepo).errors == []

    on_update = cast(%{post | id: post.id + 1}, %{"title" => "hello"}, ~w(title), ~w())
    assert validate_unique(on_update, :title, on: TestRepo).errors == []
  end

  test "validate_unique/3 with scope" do
    import Ecto.Changeset
    TestRepo.insert(%Post{title: "hello", text: "world"})

    on_insert = cast(%Post{}, %{"title" => "hello", "text" => "elixir"}, ~w(title), ~w(text))
    assert validate_unique(on_insert, :title, on: TestRepo).errors == [title: "has already been taken"]
    assert validate_unique(on_insert, :title, scope: [:text], on: TestRepo).errors == []

    on_insert = cast(%Post{}, %{"title" => "hello", "text" => nil}, ~w(title), ~w(text))
    assert validate_unique(on_insert, :title, scope: [:text], on: TestRepo).errors == []

    assert_raise(Ecto.QueryError, fn ->
      validate_unique(on_insert, :title, scope: [:non_existent], on: TestRepo).errors == []
    end)
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
    TestRepo.insert(%Custom{uuid: "01abcdef01abcdef"})
    TestRepo.insert(%Custom{uuid: "02abcdef02abcdef"})

    assert %Custom{uuid: "01abcdef01abcdef", __meta__: %{state: :loaded}} =
           TestRepo.get(Custom, "01abcdef01abcdef")

    assert %Custom{uuid: "02abcdef02abcdef", __meta__: %{state: :loaded}} =
           TestRepo.get(Custom, "02abcdef02abcdef")

    assert nil = TestRepo.get(Custom, "03abcdef03abcdef")
  end

  test "get(!) with custom source" do
    custom = %Custom{uuid: "01abcdef01abcdef"}
    custom = Ecto.Model.put_source(custom, "posts")
    TestRepo.insert(custom)

    assert %Custom{uuid: "01abcdef01abcdef", __meta__: %{source: "posts"}} =
           TestRepo.get(from(c in {"posts", Custom}), "01abcdef01abcdef")
  end

  test "get_by(!)" do
    post1 = TestRepo.insert(%Post{title: "1", text: "hai"})
    post2 = TestRepo.insert(%Post{title: "2", text: "hello"})

    assert post1 == TestRepo.get_by(Post, id: post1.id)
    assert post1 == TestRepo.get_by(Post, text: post1.text)
    assert post1 == TestRepo.get_by(Post, id: post1.id, text: post1.text)
    assert post2 == TestRepo.get_by(Post, id: to_string(post2.id)) # With casting
    assert nil   == TestRepo.get_by(Post, text: "hey")
    assert nil   == TestRepo.get_by(Post, id: post2.id, text: "hey")

    assert post1 == TestRepo.get_by!(Post, id: post1.id)
    assert post1 == TestRepo.get_by!(Post, text: post1.text)
    assert post1 == TestRepo.get_by!(Post, id: post1.id, text: post1.text)
    assert post2 == TestRepo.get_by!(Post, id: to_string(post2.id)) # With casting

    assert_raise Ecto.NoResultsError, fn ->
      TestRepo.get_by!(Post, id: post2.id, text: "hey")
    end
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
    assert %Post{} = TestRepo.insert(%Post{title: "hai"})
    assert %Post{} = TestRepo.insert(%Post{title: "hai"})

    assert_raise Ecto.MultipleResultsError, fn ->
      TestRepo.one(from p in Post, where: p.title == "hai")
    end

    assert_raise Ecto.MultipleResultsError, fn ->
      TestRepo.one!(from p in Post, where: p.title == "hai")
    end
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

  test "update all with joins" do
    user = TestRepo.insert(%User{name: "Tester"})
    post = TestRepo.insert(%Post{title: "foo"})
    comment = TestRepo.insert(%Comment{text: "hey", author_id: user.id, post_id: post.id})

    query = from(c in Comment, join: u in User, on: u.id == c.author_id, where: c.post_id in ^[post.id])
    assert 1 = TestRepo.update_all(query, text: "hoo")

    assert %Comment{text: "hoo"} = TestRepo.get(Comment, comment.id)
  end

  test "update all with filter" do
    assert %Post{id: id1} = TestRepo.insert(%Post{title: "1"})
    assert %Post{id: id2} = TestRepo.insert(%Post{title: "2"})
    assert %Post{id: id3} = TestRepo.insert(%Post{title: "3"})

    query = from(p in Post, where: p.title == "1" or p.title == "2")
    assert 2 = TestRepo.update_all(query, title: "x", text: ^"y")

    assert %Post{title: "x", text: "y"} = TestRepo.get(Post, id1)
    assert %Post{title: "x", text: "y"} = TestRepo.get(Post, id2)
    assert %Post{title: "3", text: nil} = TestRepo.get(Post, id3)
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
    assert %Post{id: id1} = TestRepo.insert(%Post{title: "1", visits: 0})
    assert %Post{id: id2} = TestRepo.insert(%Post{title: "2", visits: 1})

    # Expressions
    query = from p in Post, where: p.id > 0
    assert 2 = TestRepo.update_all(p in query, visits: fragment("? + 2", p.visits))

    assert %Post{visits: 2} = TestRepo.get(Post, id1)
    assert %Post{visits: 3} = TestRepo.get(Post, id2)

    # Nil values
    assert 2 = TestRepo.update_all(p in Post, visits: nil)

    assert %Post{visits: nil} = TestRepo.get(Post, id1)
    assert %Post{visits: nil} = TestRepo.get(Post, id2)
  end

  test "update all with casting and dumping" do
    text = "hai"
    date = Ecto.DateTime.utc
    assert %Post{id: id1} = TestRepo.insert(%Post{})
    assert 1 = TestRepo.update_all(p in Post, text: ^text, counter: ^to_string(id1), inserted_at: ^date)
    assert %Post{text: "hai", counter: ^id1, inserted_at: ^date} = TestRepo.get(Post, id1)

    text = "hai"
    date = {{2010, 4, 17}, {14, 00, 00, 00}}
    assert %Comment{id: id2} = TestRepo.insert(%Comment{})
    assert 1 = TestRepo.update_all(p in Comment, text: ^text, posted: ^date)
    assert %Comment{text: "hai", posted: ^date} = TestRepo.get(Comment, id2)

    date = {{1955, 11, 12}, {6, 38, 01, 0}}
    assert 1 = TestRepo.update_all(p in Comment, text: ^text, posted: ^date)
    assert %Comment{text: "hai", posted: ^date} = TestRepo.get(Comment, id2)
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

  test "delete all with joins" do
    user = TestRepo.insert(%User{name: "Tester"})
    post = TestRepo.insert(%Post{title: "foo"})
    TestRepo.insert(%Comment{text: "hey", author_id: user.id, post_id: post.id})
    TestRepo.insert(%Comment{text: "foo", author_id: user.id, post_id: post.id})
    TestRepo.insert(%Comment{text: "bar", author_id: user.id})

    query = from(c in Comment, join: u in User, on: u.id == c.author_id, where: c.post_id in ^[post.id])
    assert 2 = TestRepo.delete_all(query)

    assert [%Comment{}] = TestRepo.all(Comment)
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

    query = from(p in Post, join: c in assoc(p, :comments), select: {p, c}, order_by: p.id)
    [{^post, ^c1}, {^post, ^c2}] = TestRepo.all(query)
  end

  test "has_one association join" do
    post = TestRepo.insert(%Post{title: "1", text: "hi"})
    p1 = TestRepo.insert(%Permalink{url: "hey", post_id: post.id})
    p2 = TestRepo.insert(%Permalink{url: "heya", post_id: post.id})

    query = from(p in Post, join: c in assoc(p, :permalink), select: {p, c}, order_by: c.id)
    [{^post, ^p1}, {^post, ^p2}] = TestRepo.all(query)
  end

  test "belongs_to association join" do
    post = TestRepo.insert(%Post{title: "1"})
    p1 = TestRepo.insert(%Permalink{url: "hey", post_id: post.id})
    p2 = TestRepo.insert(%Permalink{url: "heya", post_id: post.id})

    query = from(p in Permalink, join: c in assoc(p, :post), select: {p, c}, order_by: p.id)
    [{^p1, ^post}, {^p2, ^post}] = TestRepo.all(query)
  end

  ## Assocs

  test "has_many assoc" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "1"})

    %Comment{id: cid1} = TestRepo.insert(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert(%Comment{text: "2", post_id: p1.id})
    %Comment{id: cid3} = TestRepo.insert(%Comment{text: "3", post_id: p2.id})

    [c1, c2] = TestRepo.all Ecto.Model.assoc(p1, :comments)
    assert c1.id == cid1
    assert c2.id == cid2

    [c1, c2, c3] = TestRepo.all Ecto.Model.assoc([p1, p2], :comments)
    assert c1.id == cid1
    assert c2.id == cid2
    assert c3.id == cid3
  end

  test "has_one assoc" do
    p1 = TestRepo.insert(%Post{title: "1"})
    p2 = TestRepo.insert(%Post{title: "2"})

    %Permalink{id: lid1} = TestRepo.insert(%Permalink{url: "1", post_id: p1.id})
    %Permalink{}         = TestRepo.insert(%Permalink{url: "2"})
    %Permalink{id: lid3} = TestRepo.insert(%Permalink{url: "3", post_id: p2.id})

    [l1, l3] = TestRepo.all Ecto.Model.assoc([p1, p2], :permalink)
    assert l1.id == lid1
    assert l3.id == lid3
  end

  test "belongs_to assoc" do
    %Post{id: pid1} = TestRepo.insert(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert(%Post{title: "2"})

    l1 = TestRepo.insert(%Permalink{url: "1", post_id: pid1})
    l2 = TestRepo.insert(%Permalink{url: "2"})
    l3 = TestRepo.insert(%Permalink{url: "3", post_id: pid2})

    assert [p1, p2] = TestRepo.all Ecto.Model.assoc([l1, l2, l3], :post)
    assert p1.id == pid1
    assert p2.id == pid2
  end

  test "has_many through assoc" do
    %Post{id: pid1} = p1 = TestRepo.insert(%Post{})
    %Post{id: pid2} = p2 = TestRepo.insert(%Post{})

    %User{id: uid1} = TestRepo.insert(%User{name: "zzz"})
    %User{id: uid2} = TestRepo.insert(%User{name: "aaa"})

    %Comment{} = TestRepo.insert(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert(%Comment{post_id: pid1, author_id: uid1})
    %Comment{} = TestRepo.insert(%Comment{post_id: pid1, author_id: uid2})
    %Comment{} = TestRepo.insert(%Comment{post_id: pid2, author_id: uid2})

    [u2, u1] = TestRepo.all Ecto.Model.assoc([p1, p2], :comments_authors)
                            |> order_by([a], a.name)
    assert u1.id == uid1
    assert u2.id == uid2
  end

  test "optimistic locking in update/delete operations" do
    import Ecto.Changeset, only: [cast: 4]
    base_post = TestRepo.insert(%Permalink{})

    cs_ok = cast(base_post, %{"url" => "http://foo.bar"}, ~w(url), ~w())
    TestRepo.update(cs_ok)

    cs_stale = cast(base_post, %{"url" => "http://foo.baz"}, ~w(url), ~w())
    assert_raise Ecto.StaleModelError, fn -> TestRepo.update(cs_stale) end
    assert_raise Ecto.StaleModelError, fn -> TestRepo.delete(cs_stale) end
  end

  @tag :uses_usec
  test "insert and fetch a model with timestamps with usec" do
    p1 = TestRepo.insert(%PostUsecTimestamps{title: "hello"})
    assert [p1] == TestRepo.all(PostUsecTimestamps)
  end
end
