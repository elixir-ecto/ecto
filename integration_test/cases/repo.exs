Code.require_file "../support/types.exs", __DIR__

defmodule Ecto.Integration.RepoTest do
  use Ecto.Integration.Case

  alias Ecto.Integration.TestRepo
  import Ecto.Query

  alias Ecto.Integration.Post
  alias Ecto.Integration.User
  alias Ecto.Integration.PostUsecTimestamps
  alias Ecto.Integration.Comment
  alias Ecto.Integration.Permalink
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
    TestRepo.insert!(%Post{title: "hello"})

    assert []  = TestRepo.all from p in Post, where: p.title in []
    assert []  = TestRepo.all from p in Post, where: p.title in ["1", "2", "3"]
    assert []  = TestRepo.all from p in Post, where: p.title in ^[]

    assert [_] = TestRepo.all from p in Post, where: not p.title in []
    assert [_] = TestRepo.all from p in Post, where: p.title in ["1", "hello", "3"]
    assert [_] = TestRepo.all from p in Post, where: p.title in ["1", ^"hello", "3"]
    assert [_] = TestRepo.all from p in Post, where: p.title in ^["1", "hello", "3"]
  end

  test "fetch without model" do
    %Post{} = TestRepo.insert!(%Post{title: "title1"})
    %Post{} = TestRepo.insert!(%Post{title: "title2"})

    assert ["title1", "title2"] =
      TestRepo.all(from(p in "posts", order_by: p.title, select: p.title))

    assert [_] =
      TestRepo.all(from(p in "posts", where: p.title == "title1", select: p.id))
  end

  test "insert, update and delete" do
    post = %Post{title: "create and delete single", text: "fetch empty"}
    meta = post.__meta__

    deleted_meta = put_in meta.state, :deleted
    assert %Post{} = to_be_deleted = TestRepo.insert!(post)
    assert %Post{__meta__: ^deleted_meta} = TestRepo.delete!(to_be_deleted)

    loaded_meta = put_in meta.state, :loaded
    assert %Post{__meta__: ^loaded_meta} = TestRepo.insert!(post)

    post = TestRepo.one(Post)
    assert post.__meta__.state == :loaded
    assert post.inserted_at

    post = %{post | text: "coming very soon..."}
    post = put_in post.__meta__.state, :built
    assert %Post{__meta__: ^loaded_meta} = TestRepo.update!(post)
  end

  test "insert and update with changeset" do
    # On insert we merge the fields and changes
    changeset = Ecto.Changeset.cast(%Post{text: "x", title: "wrong"},
                                    %{"title" => "hello", "temp" => "unknown"}, ~w(title temp), ~w())

    post = TestRepo.insert!(changeset)
    assert %Post{text: "x", title: "hello", temp: "unknown"} = post
    assert %Post{text: "x", title: "hello", temp: "temp"} = TestRepo.get!(Post, post.id)

    # On update we merge only fields, direct model changes are discarded
    changeset = Ecto.Changeset.cast(%{post | text: "y"},
                                    %{"title" => "world", "temp" => "unknown"}, ~w(title temp), ~w())

    assert %Post{text: "y", title: "world", temp: "unknown"} = TestRepo.update!(changeset)
    assert %Post{text: "x", title: "world", temp: "temp"} = TestRepo.get!(Post, post.id)
  end

  test "insert and update with empty changeset" do
    # On insert we merge the fields and changes
    changeset = Ecto.Changeset.cast(%Permalink{}, %{}, ~w(), ~w())
    assert %Permalink{} = permalink = TestRepo.insert!(changeset)

    # Assert we can update the same value twice,
    # without changes, without triggering stale errors.
    changeset = Ecto.Changeset.cast(permalink, %{}, ~w(), ~w())
    assert TestRepo.update!(changeset) == permalink
    assert TestRepo.update!(changeset) == permalink
  end

  test "insert with no primary key" do
    assert %Barebone{num: nil} = TestRepo.insert!(%Barebone{})
    assert %Barebone{num: 13} = TestRepo.insert!(%Barebone{num: 13})
  end

  @tag :read_after_writes
  test "insert and update with changeset read after writes" do
    defmodule RAW do
      use Ecto.Model

      schema "posts" do
        field :counter, :integer, read_after_writes: true
        field :visits, :integer
      end
    end

    changeset = Ecto.Changeset.cast(struct(RAW, %{}), %{}, ~w(), ~w())

    # There is no dirty tracking on insert, even with changesets,
    # so database defaults never actually kick in.
    assert %{id: cid, counter: nil} = raw = TestRepo.insert!(changeset)

    # Set the counter to 11, so we can read it soon
    TestRepo.update!(%{raw | counter: 11})

    # Now, a combination of dirty tracking with read_after_writes,
    # allow us to see the actual counter value.
    changeset = Ecto.Changeset.cast(raw, %{"visits" => "0"}, ~w(visits), ~w())
    assert %{id: ^cid, counter: 11, visits: 0} = TestRepo.update!(changeset)
  end

  test "insert autogenerates for custom type" do
    post = TestRepo.insert!(%Post{uuid: nil})
    assert byte_size(post.uuid) == 36
    assert TestRepo.get_by(Post, uuid: post.uuid) == post
  end

  @tag :id_type
  test "insert autogenerates for custom id type" do
    defmodule ID do
      use Ecto.Model

      @primary_key {:id, Elixir.Custom.Permalink, autogenerate: true}
      schema "posts" do
      end
    end

    id = TestRepo.insert!(struct(ID, id: nil))
    assert id.id
    assert TestRepo.get_by(ID, id: "#{id.id}-hello") == id
  end

  @tag :id_type
  @tag :assigns_id_type
  test "insert with user-assigned primary key" do
    assert %Post{id: 1} = TestRepo.insert!(%Post{id: 1})
  end

  @tag :id_type
  @tag :assigns_id_type
  test "insert and update with user-assigned primary key in changeset" do
    changeset = Ecto.Changeset.cast(%Post{id: 11}, %{"id" => "13"}, ~w(id), ~w())
    assert %Post{id: 13} = post = TestRepo.insert!(changeset)

    changeset = Ecto.Changeset.cast(post, %{"id" => "15"}, ~w(id), ~w())
    assert %Post{id: 15} = TestRepo.update!(changeset)
  end

  test "insert autogenerates for binary id type" do
    custom = TestRepo.insert!(%Custom{bid: nil})
    assert custom.bid
    assert TestRepo.get(Custom, custom.bid)
    assert TestRepo.delete!(custom)
    refute TestRepo.get(Custom, custom.bid)
  end

  @tag :uses_usec
  test "insert and fetch a model with timestamps with usec" do
    p1 = TestRepo.insert!(%PostUsecTimestamps{title: "hello"})
    assert [p1] == TestRepo.all(PostUsecTimestamps)
  end

  test "optimistic locking in update/delete operations" do
    import Ecto.Changeset, only: [cast: 4]
    base_post = TestRepo.insert!(%Comment{})

    cs_ok = cast(base_post, %{"text" => "foo.bar"}, ~w(text), ~w())
    TestRepo.update!(cs_ok)

    cs_stale = cast(base_post, %{"text" => "foo.baz"}, ~w(text), ~w())
    assert_raise Ecto.StaleModelError, fn -> TestRepo.update!(cs_stale) end

    assert_raise Ecto.StaleModelError, fn -> TestRepo.delete!(base_post) end
  end

  @tag :unique_constraint
  test "unique constraint" do
    changeset = Ecto.Changeset.change(%Post{}, uuid: Ecto.UUID.generate())
    {:ok, _}  = TestRepo.insert(changeset)

    exception =
      assert_raise Ecto.ConstraintError, ~r/constraint error when attempting to insert model/, fn ->
        changeset
        |> TestRepo.insert()
      end

    assert exception.message =~ "unique: posts_uuid_index"
    assert exception.message =~ "The changeset has not defined any constraint."

    message = ~r/constraint error when attempting to insert model/
    exception =
      assert_raise Ecto.ConstraintError, message, fn ->
        changeset
        |> Ecto.Changeset.unique_constraint(:uuid, name: :posts_email_changeset)
        |> TestRepo.insert()
      end

    assert exception.message =~ "unique: posts_email_changeset"

    {:error, changeset} =
      changeset
      |> Ecto.Changeset.unique_constraint(:uuid)
      |> TestRepo.insert()
    assert changeset.errors == [uuid: "has already been taken"]
  end

  @tag :id_type
  @tag :unique_constraint
  test "unique constraint with binary_id" do
    changeset = Ecto.Changeset.change(%Custom{}, uuid: Ecto.UUID.generate())
    {:ok, _}  = TestRepo.insert(changeset)

    {:error, changeset} =
      changeset
      |> Ecto.Changeset.unique_constraint(:uuid)
      |> TestRepo.insert()
    assert changeset.errors == [uuid: "has already been taken"]
  end

  @tag :foreign_key_constraint
  test "foreign key constraint" do
    changeset = Ecto.Changeset.change(%Comment{post_id: 0})

    exception =
      assert_raise Ecto.ConstraintError, ~r/constraint error when attempting to insert model/, fn ->
        changeset
        |> TestRepo.insert()
      end

    assert exception.message =~ "foreign_key: comments_post_id_fkey"
    assert exception.message =~ "The changeset has not defined any constraint."

    message = ~r/constraint error when attempting to insert model/
    exception =
      assert_raise Ecto.ConstraintError, message, fn ->
        changeset
        |> Ecto.Changeset.foreign_key_constraint(:post_id, name: :comments_post_id_other)
        |> TestRepo.insert()
      end

    assert exception.message =~ "foreign_key: comments_post_id_other"

    {:error, changeset} =
      changeset
      |> Ecto.Changeset.foreign_key_constraint(:post_id)
      |> TestRepo.insert()
    assert changeset.errors == [post_id: "does not exist"]
  end

 @tag :foreign_key_constraint
  test "assoc constraint" do
    changeset = Ecto.Changeset.change(%Comment{post_id: 0})

    exception =
      assert_raise Ecto.ConstraintError, ~r/constraint error when attempting to insert model/, fn ->
        changeset
        |> TestRepo.insert()
      end

    assert exception.message =~ "foreign_key: comments_post_id_fkey"
    assert exception.message =~ "The changeset has not defined any constraint."

    message = ~r/constraint error when attempting to insert model/
    exception =
      assert_raise Ecto.ConstraintError, message, fn ->
        changeset
        |> Ecto.Changeset.assoc_constraint(:post, name: :comments_post_id_other)
        |> TestRepo.insert()
      end

    assert exception.message =~ "foreign_key: comments_post_id_other"

    {:error, changeset} =
      changeset
      |> Ecto.Changeset.assoc_constraint(:post)
      |> TestRepo.insert()
    assert changeset.errors == [post: "does not exist"]
  end

  @tag :foreign_key_constraint
  test "no assoc constraint" do
    user = TestRepo.insert!(%User{})
    TestRepo.insert!(%Permalink{user_id: user.id})

    exception =
      assert_raise Ecto.ConstraintError, ~r/constraint error when attempting to delete model/, fn ->
        TestRepo.delete!(user)
      end

    assert exception.message =~ "foreign_key: permalinks_user_id_fkey"
    assert exception.message =~ "The changeset has not defined any constraint."

    message = ~r/constraint error when attempting to delete model/
    exception =
      assert_raise Ecto.ConstraintError, message, fn ->
        user
        |> Ecto.Changeset.change
        |> Ecto.Changeset.no_assoc_constraint(:permalinks, name: :permalinks_user_id_pther)
        |> TestRepo.delete()
      end

    assert exception.message =~ "foreign_key: permalinks_user_id_pther"

    {:error, changeset} =
      user
      |> Ecto.Changeset.change
      |> Ecto.Changeset.no_assoc_constraint(:permalinks)
      |> TestRepo.delete()
    assert changeset.errors == [permalinks: "are still associated to this entry"]
  end

  test "get(!)" do
    post1 = TestRepo.insert!(%Post{title: "1", text: "hai"})
    post2 = TestRepo.insert!(%Post{title: "2", text: "hai"})

    assert post1 == TestRepo.get(Post, post1.id)
    assert post2 == TestRepo.get(Post, to_string post2.id) # With casting

    assert post1 == TestRepo.get!(Post, post1.id)
    assert post2 == TestRepo.get!(Post, to_string post2.id) # With casting

    TestRepo.delete!(post1)

    assert nil   == TestRepo.get(Post, post1.id)
    assert_raise Ecto.NoResultsError, fn ->
      TestRepo.get!(Post, post1.id)
    end
  end

  test "get(!) with custom source" do
    custom = Ecto.Model.put_source(%Custom{}, "posts")
    custom = TestRepo.insert!(custom)
    bid    = custom.bid
    assert %Custom{bid: ^bid, __meta__: %{source: {nil, "posts"}}} =
           TestRepo.get(from(c in {"posts", Custom}), bid)
  end

  test "get_by(!)" do
    post1 = TestRepo.insert!(%Post{title: "1", text: "hai"})
    post2 = TestRepo.insert!(%Post{title: "2", text: "hello"})

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
    post1 = TestRepo.insert!(%Post{title: "1", text: "hai"})
    post2 = TestRepo.insert!(%Post{title: "2", text: "hai"})

    assert post1 == TestRepo.one(from p in Post, where: p.id == ^post1.id)
    assert post2 == TestRepo.one(from p in Post, where: p.id == ^to_string post2.id) # With casting
    assert nil   == TestRepo.one(from p in Post, where: is_nil(p.id))

    assert post1 == TestRepo.one!(from p in Post, where: p.id == ^post1.id)
    assert post2 == TestRepo.one!(from p in Post, where: p.id == ^to_string post2.id) # With casting

    assert_raise Ecto.NoResultsError, fn ->
      TestRepo.one!(from p in Post, where: is_nil(p.id))
    end
  end

  test "one(!) with multiple results" do
    assert %Post{} = TestRepo.insert!(%Post{title: "hai"})
    assert %Post{} = TestRepo.insert!(%Post{title: "hai"})

    assert_raise Ecto.MultipleResultsError, fn ->
      TestRepo.one(from p in Post, where: p.title == "hai")
    end

    assert_raise Ecto.MultipleResultsError, fn ->
      TestRepo.one!(from p in Post, where: p.title == "hai")
    end
  end

  test "update all" do
    assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1"})
    assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2"})
    assert %Post{id: id3} = TestRepo.insert!(%Post{title: "3"})

    assert {3, nil} = TestRepo.update_all(Post, set: [title: "x"])

    assert %Post{title: "x"} = TestRepo.get(Post, id1)
    assert %Post{title: "x"} = TestRepo.get(Post, id2)
    assert %Post{title: "x"} = TestRepo.get(Post, id3)

    assert {3, nil} = TestRepo.update_all("posts", set: [title: nil])

    assert %Post{title: nil} = TestRepo.get(Post, id1)
    assert %Post{title: nil} = TestRepo.get(Post, id2)
    assert %Post{title: nil} = TestRepo.get(Post, id3)
  end

  test "update all with filter" do
    assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1"})
    assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2"})
    assert %Post{id: id3} = TestRepo.insert!(%Post{title: "3"})

    query = from(p in Post, where: p.title == "1" or p.title == "2",
                            update: [set: [text: ^"y"]])
    assert {2, nil} = TestRepo.update_all(query, set: [title: "x"])

    assert %Post{title: "x", text: "y"} = TestRepo.get(Post, id1)
    assert %Post{title: "x", text: "y"} = TestRepo.get(Post, id2)
    assert %Post{title: "3", text: nil} = TestRepo.get(Post, id3)
  end

  test "update all no entries" do
    assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1"})
    assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2"})
    assert %Post{id: id3} = TestRepo.insert!(%Post{title: "3"})

    query = from(p in Post, where: p.title == "4")
    assert {0, nil} = TestRepo.update_all(query, set: [title: "x"])

    assert %Post{title: "1"} = TestRepo.get(Post, id1)
    assert %Post{title: "2"} = TestRepo.get(Post, id2)
    assert %Post{title: "3"} = TestRepo.get(Post, id3)
  end

  test "update all increment syntax" do
    assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1", visits: 0})
    assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2", visits: 1})

    # Positive
    query = from p in Post, where: not is_nil(p.id), update: [inc: [visits: 2]]
    assert {2, nil} = TestRepo.update_all(query, [])

    assert %Post{visits: 2} = TestRepo.get(Post, id1)
    assert %Post{visits: 3} = TestRepo.get(Post, id2)

    # Negative
    query = from p in Post, where: not is_nil(p.id), update: [inc: [visits: -1]]
    assert {2, nil} = TestRepo.update_all(query, [])

    assert %Post{visits: 1} = TestRepo.get(Post, id1)
    assert %Post{visits: 2} = TestRepo.get(Post, id2)
  end

  @tag :id_type
  test "update all with casting and dumping on id type field" do
    assert %Post{id: id1} = TestRepo.insert!(%Post{})
    assert {1, nil} = TestRepo.update_all(Post, set: [counter: to_string(id1)])
    assert %Post{counter: ^id1} = TestRepo.get(Post, id1)
  end

  test "update all with casting and dumping" do
    text = "hai"
    date = Ecto.DateTime.utc
    assert %Post{id: id1} = TestRepo.insert!(%Post{})

    assert {1, nil} = TestRepo.update_all(Post, set: [text: text, inserted_at: date])
    assert %Post{text: "hai", inserted_at: ^date} = TestRepo.get(Post, id1)
  end

  test "delete all" do
    assert %Post{} = TestRepo.insert!(%Post{title: "1", text: "hai"})
    assert %Post{} = TestRepo.insert!(%Post{title: "2", text: "hai"})
    assert %Post{} = TestRepo.insert!(%Post{title: "3", text: "hai"})

    assert {3, nil} = TestRepo.delete_all(Post)
    assert [] = TestRepo.all(Post)
  end

  test "delete all with filter" do
    assert %Post{} = TestRepo.insert!(%Post{title: "1", text: "hai"})
    assert %Post{} = TestRepo.insert!(%Post{title: "2", text: "hai"})
    assert %Post{} = TestRepo.insert!(%Post{title: "3", text: "hai"})

    query = from(p in Post, where: p.title == "1" or p.title == "2")
    assert {2, nil} = TestRepo.delete_all(query)
    assert [%Post{}] = TestRepo.all(Post)
  end

  test "delete all no entries" do
    assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1", text: "hai"})
    assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2", text: "hai"})
    assert %Post{id: id3} = TestRepo.insert!(%Post{title: "3", text: "hai"})

    query = from(p in Post, where: p.title == "4")
    assert {0, nil} = TestRepo.delete_all(query)
    assert %Post{title: "1"} = TestRepo.get(Post, id1)
    assert %Post{title: "2"} = TestRepo.get(Post, id2)
    assert %Post{title: "3"} = TestRepo.get(Post, id3)
  end

  test "virtual field" do
    assert %Post{id: id} = TestRepo.insert!(%Post{title: "1", text: "hai"})
    assert TestRepo.get(Post, id).temp == "temp"
  end

  ## Assocs

  test "has_many assoc" do
    p1 = TestRepo.insert!(%Post{title: "1"})
    p2 = TestRepo.insert!(%Post{title: "1"})

    %Comment{id: cid1} = TestRepo.insert!(%Comment{text: "1", post_id: p1.id})
    %Comment{id: cid2} = TestRepo.insert!(%Comment{text: "2", post_id: p1.id})
    %Comment{id: cid3} = TestRepo.insert!(%Comment{text: "3", post_id: p2.id})

    [c1, c2] = TestRepo.all Ecto.Model.assoc(p1, :comments)
    assert c1.id == cid1
    assert c2.id == cid2

    [c1, c2, c3] = TestRepo.all Ecto.Model.assoc([p1, p2], :comments)
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

    [l1, l3] = TestRepo.all Ecto.Model.assoc([p1, p2], :permalink)
    assert l1.id == lid1
    assert l3.id == lid3
  end

  test "belongs_to assoc" do
    %Post{id: pid1} = TestRepo.insert!(%Post{title: "1"})
    %Post{id: pid2} = TestRepo.insert!(%Post{title: "2"})

    l1 = TestRepo.insert!(%Permalink{url: "1", post_id: pid1})
    l2 = TestRepo.insert!(%Permalink{url: "2"})
    l3 = TestRepo.insert!(%Permalink{url: "3", post_id: pid2})

    assert [p1, p2] = TestRepo.all Ecto.Model.assoc([l1, l2, l3], :post)
    assert p1.id == pid1
    assert p2.id == pid2
  end

  test "has_one nested assoc" do
    changeset = Ecto.Changeset.change(%Post{title: "1"}, permalink: %Permalink{url: "1"})
    p1 = TestRepo.insert!(changeset)
    assert p1.permalink.id
    assert p1.permalink.post_id == p1.id
    assert p1.permalink.url == "1"
    p1 = TestRepo.get!(from(p in Post, preload: [:permalink]), p1.id)
    assert p1.permalink.url == "1"

    changeset = Ecto.Changeset.change(p1, permalink: %Permalink{url: "2"})
    p1 = TestRepo.update!(changeset)
    assert p1.permalink.id
    assert p1.permalink.post_id == p1.id
    assert p1.permalink.url == "2"
    p1 = TestRepo.get!(from(p in Post, preload: [:permalink]), p1.id)
    assert p1.permalink.url == "2"

    changeset = Ecto.Changeset.change(p1, permalink: nil)
    p1 = TestRepo.update!(changeset)
    refute p1.permalink
    p1 = TestRepo.get!(from(p in Post, preload: [:permalink]), p1.id)
    refute p1.permalink

    assert [0] == TestRepo.all(from(p in Permalink, select: count(p.id)))
  end

  test "has_many nested assoc" do
    c1 = %Comment{text: "1"}
    c2 = %Comment{text: "2"}

    changeset = Ecto.Changeset.change(%Post{title: "1"}, comments: [c1])
    p1 = TestRepo.insert!(changeset)
    [c1] = p1.comments
    assert c1.id
    assert c1.post_id == p1.id
    p1 = TestRepo.get!(from(p in Post, preload: [:comments]), p1.id)
    [c1] = p1.comments
    assert c1.text == "1"

    changeset = Ecto.Changeset.change(p1, comments: [c1, c2])
    p1 = TestRepo.update!(changeset)
    [_c1, c2] = p1.comments |> Enum.sort_by(&(&1.id))
    assert c2.id
    assert c2.post_id == p1.id
    p1 = TestRepo.get!(from(p in Post, preload: [:comments]), p1.id)
    [c1, c2] = p1.comments |> Enum.sort_by(&(&1.id))
    assert c1.text == "1"
    assert c2.text == "2"

    changeset = Ecto.Changeset.change(p1, comments: [])
    p1 = TestRepo.update!(changeset)
    assert p1.comments == []
    p1 = TestRepo.get!(from(p in Post, preload: [:comments]), p1.id)
    assert p1.comments == []

    assert [0] == TestRepo.all(from(c in Comment, select: count(c.id)))
  end

  @tag :unique_constraint
  test "has_many assoc with constraints" do
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
    changeset = Ecto.Changeset.cast(author, %{"posts" => posts_params}, ~w(posts))
    author = TestRepo.update! changeset
    assert Enum.map(author.posts, &(&1.title)) == ["fresh", "fresh"]
  end

  @tag :transaction
  test "rollbacks failed nested assocs" do
    permalink_changeset = %{Ecto.Changeset.change(%Permalink{url: "1"}) | valid?: false}
    changeset = Ecto.Changeset.change(%Post{title: "1"}, permalink: permalink_changeset)
    assert {:error, changeset} = TestRepo.insert(changeset)
    assert changeset.model.__struct__ == Post
    refute changeset.valid?
    assert [0] == TestRepo.all(from(p in Post, select: count(p.id)))
    assert [0] == TestRepo.all(from(p in Permalink, select: count(p.id)))
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

  test "has_many assoc on delete fetches and deletes" do
    post = TestRepo.insert!(%Post{})
    TestRepo.insert!(%Permalink{post_id: post.id})
    TestRepo.delete!(post)

    assert TestRepo.all(Permalink) == []
    assert Process.get(Permalink) == :on_delete
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
end
