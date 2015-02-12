defmodule Ecto.Integration.RepoTest do
  use Ecto.Integration.Case

  require Ecto.Integration.TestRepo, as: TestRepo
  import Ecto.Query

  alias Ecto.Integration.Post
  alias Ecto.Integration.Comment
  alias Ecto.Integration.Permalink
  alias Ecto.Integration.User
  alias Ecto.Integration.Custom
  alias Ecto.Integration.Barebone

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

    assert %Post{__state__: :loaded} = TestRepo.insert(post)
    assert %Post{} = to_be_deleted = TestRepo.insert(post)
    assert %Post{__state__: :deleted} = TestRepo.delete(to_be_deleted)

    post = TestRepo.one(Post)
    assert post.__state__ == :loaded
    assert post.inserted_at
    assert post.updated_at

    post = %{post | text: "coming very soon...", __state__: :built}
    assert %Post{__state__: :loaded} = TestRepo.update(post)
  end

  test "insert with no primary key" do
    assert %Barebone{num: nil} = TestRepo.insert(%Barebone{})
    assert %Barebone{num: 13} = TestRepo.insert(%Barebone{num: 13})
  end

  test "insert and update with changeset" do
    # On insert we merge the fields and changes
    changeset = Ecto.Changeset.cast(%{"title" => "hello", "temp" => "unknown"},
                                    %Post{text: "x", title: "wrong"}, ~w(title temp), ~w())

    post = TestRepo.insert(changeset)
    assert %Post{text: "x", title: "hello", temp: "unknown"} = post
    assert %Post{text: "x", title: "hello", temp: "temp"} = TestRepo.get!(Post, post.id)

    # On update we merge only fields
    changeset = Ecto.Changeset.cast(%{"title" => "world", "temp" => "unknown"},
                                    %{post | text: "y"}, ~w(title temp), ~w())

    assert %Post{text: "y", title: "world", temp: "unknown"} = TestRepo.update(changeset)
    assert %Post{text: "x", title: "world", temp: "temp"} = TestRepo.get!(Post, post.id)
  end

  @tag :assigns_primary_key
  test "insert with user-assigned primary key" do
    assert %Post{id: 1} = TestRepo.insert(%Post{id: 1})
  end

  @tag :assigns_primary_key
  test "insert and update with user-assigned primary key in changeset" do
    changeset = Ecto.Changeset.cast(%{"id" => "13"}, %Post{id: 11}, ~w(id), ~w())
    assert %Post{id: 13} = post = TestRepo.insert(changeset)

    changeset = Ecto.Changeset.cast(%{"id" => "15"}, post, ~w(id), ~w())
    assert %Post{id: 15} = TestRepo.update(changeset)

    # We even allow a nil primary key to be set via the
    # changeset but that causes crashes
    changeset = Ecto.Changeset.cast(%{"id" => nil}, %Post{id: 11}, ~w(), ~w(id))
    assert catch_error(TestRepo.insert(changeset))
  end

  test "insert and update with changeset dirty tracking" do
    changeset = Ecto.Changeset.cast(%{}, %Post{}, ~w(), ~w())

    # There is no dirty tracking on insert, even with changesets,
    # so database defaults never actually kick in.
    assert %Post{id: pid, counter: nil} = post = TestRepo.insert(changeset)

    # Set the counter to 11, so we can read it soon
    TestRepo.update(%{post | counter: 11})

    # Now, a combination of dirty tracking with read_after_writes,
    # allow us to see the actual counter value.
    changeset = Ecto.Changeset.cast(%{"title" => "hello"}, post, ~w(title), ~w())
    assert %Post{id: ^pid, counter: 11, title: "hello"} = post = TestRepo.update(changeset)

    # Let's change the counter once more, so we can read it soon
    TestRepo.update(%{post | counter: 13})

    # And the value will be refreshed even if there are no changes
    changeset = Ecto.Changeset.cast(%{}, post, ~w(), ~w())
    assert %Post{id: ^pid, counter: 13, title: "hello"} = TestRepo.update(changeset)
  end

  test "validate_unique/3" do
    import Ecto.Changeset
    post = TestRepo.insert(%Post{title: "HELLO"})

    on_insert = cast(%{"title" => "HELLO"}, %Post{}, ~w(title), ~w())
    assert validate_unique(on_insert, :title, on: TestRepo).errors != []

    on_insert = cast(%{"title" => "hello"}, %Post{}, ~w(title), ~w())
    assert validate_unique(on_insert, :title, on: TestRepo, downcase: true).errors != []

    on_update = cast(%{"title" => "HELLO"}, post, ~w(title), ~w())
    assert validate_unique(on_update, :title, on: TestRepo).errors == []

    on_update = cast(%{"title" => "HELLO"}, %{post | id: post.id + 1}, ~w(title), ~w())
    assert validate_unique(on_update, :title, on: TestRepo).errors != []
  end

  @tag :case_sensitive
  test "validate_unique/3 case sensitive" do
    import Ecto.Changeset
    post = TestRepo.insert(%Post{title: "HELLO"})

    on_insert = cast(%{"title" => "hello"}, %Post{}, ~w(title), ~w())
    assert validate_unique(on_insert, :title, on: TestRepo).errors == []

    on_update = cast(%{"title" => "hello"}, %{post | id: post.id + 1}, ~w(title), ~w())
    assert validate_unique(on_update, :title, on: TestRepo).errors == []
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

    assert %Custom{__state__: :loaded, foo: "01abcdef01abcdef"} == TestRepo.get(Custom, "01abcdef01abcdef")
    assert %Custom{__state__: :loaded, foo: "02abcdef02abcdef"} == TestRepo.get(Custom, "02abcdef02abcdef")
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
    date = :erlang.universaltime
    assert %Comment{id: id2} = TestRepo.insert(%Comment{})
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

    [u1, u2] = TestRepo.all Ecto.Model.assoc([p1, p2], :comments_authors)
    assert u1.id == uid1
    assert u2.id == uid2

    [u2, u1] = TestRepo.all Ecto.Model.assoc([p1, p2], :comments_authors)
                            |> order_by([a], a.name)
    assert u1.id == uid1
    assert u2.id == uid2
  end
end
