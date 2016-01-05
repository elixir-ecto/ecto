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

  test "fetch without schema" do
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
      use Ecto.Schema

      schema "comments" do
        field :text, :string
        field :lock_version, :integer, read_after_writes: true
      end
    end

    changeset = Ecto.Changeset.cast(struct(RAW, %{}), %{}, ~w(), ~w())

    # If the field is nil, we will not send it
    # and read the value back from the database.
    assert %{id: cid, lock_version: 1} = raw = TestRepo.insert!(changeset)

    # Set the counter to 11, so we can read it soon
    TestRepo.update_all from(u in RAW, where: u.id == ^cid), set: [lock_version: 11]

    # We will read back on update too
    changeset = Ecto.Changeset.cast(raw, %{"text" => "0"}, ~w(text), ~w())
    assert %{id: ^cid, lock_version: 11, text: "0"} = TestRepo.update!(changeset)
  end

  test "insert autogenerates for custom type" do
    post = TestRepo.insert!(%Post{uuid: nil})
    assert byte_size(post.uuid) == 36
    assert TestRepo.get_by(Post, uuid: post.uuid) == post
  end

  @tag :id_type
  test "insert autogenerates for custom id type" do
    defmodule ID do
      use Ecto.Schema

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

  @tag :uses_usec
  test "insert and fetch a model with timestamps with usec" do
    p1 = TestRepo.insert!(%PostUsecTimestamps{title: "hello"})
    assert [p1] == TestRepo.all(PostUsecTimestamps)
  end

  test "optimistic locking in update/delete operations" do
    import Ecto.Changeset, only: [cast: 4, optimistic_lock: 2]
    base_post = TestRepo.insert!(%Comment{})

    cs_ok =
      base_post
      |> cast(%{"text" => "foo.bar"}, ~w(text), ~w())
      |> optimistic_lock(:lock_version)
    TestRepo.update!(cs_ok)

    cs_stale = optimistic_lock(base_post, :lock_version)
    assert_raise Ecto.StaleEntryError, fn -> TestRepo.update!(cs_stale) end
    assert_raise Ecto.StaleEntryError, fn -> TestRepo.delete!(cs_stale) end
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
    assert changeset.model.__meta__.state == :built
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
    assert changeset.model.__meta__.state == :built
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
  test "no assoc constraint error" do
    user = TestRepo.insert!(%User{})
    TestRepo.insert!(%Permalink{user_id: user.id})

    exception =
      assert_raise Ecto.ConstraintError, ~r/constraint error when attempting to delete model/, fn ->
        TestRepo.delete!(user)
      end

    assert exception.message =~ "foreign_key: permalinks_user_id_fkey"
    assert exception.message =~ "The changeset has not defined any constraint."
  end

  @tag :foreign_key_constraint
  test "no assoc constraint with changeset mismatch" do
    user = TestRepo.insert!(%User{})
    TestRepo.insert!(%Permalink{user_id: user.id})

    message = ~r/constraint error when attempting to delete model/
    exception =
      assert_raise Ecto.ConstraintError, message, fn ->
        user
        |> Ecto.Changeset.change
        |> Ecto.Changeset.no_assoc_constraint(:permalink, name: :permalinks_user_id_pther)
        |> TestRepo.delete()
      end

    assert exception.message =~ "foreign_key: permalinks_user_id_pther"
  end

  @tag :foreign_key_constraint
  test "no assoc constraint with changeset match" do
    user = TestRepo.insert!(%User{})
    TestRepo.insert!(%Permalink{user_id: user.id})

    {:error, changeset} =
      user
      |> Ecto.Changeset.change
      |> Ecto.Changeset.no_assoc_constraint(:permalink)
      |> TestRepo.delete()
    assert changeset.errors == [permalink: "is still associated to this entry"]
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
    custom = Ecto.put_meta(%Custom{}, source: "posts")
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

    assert post1 == TestRepo.get_by!(Post, %{id: post1.id})

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

  test "insert all" do
    assert {2, nil} = TestRepo.insert_all("comments", [[text: "1"], %{text: "2", lock_version: 2}])
    assert [%Comment{text: "1", lock_version: 1},
            %Comment{text: "2", lock_version: 2}] = TestRepo.all(Comment)

    assert {2, nil} = TestRepo.insert_all(Post, [[], []])
    assert [%Post{}, %Post{}] = TestRepo.all(Post)

    assert {0, nil} = TestRepo.insert_all("posts", [])
  end

  test "insert all with dumping" do
    date = Ecto.DateTime.utc
    assert {2, nil} = TestRepo.insert_all(Post, [%{inserted_at: date}, %{title: "date"}])
    assert [%Post{inserted_at: ^date, title: nil},
            %Post{inserted_at: nil, title: "date"}] = TestRepo.all(Post)
  end

  test "insert all autogenerates for binary id type" do
    custom = TestRepo.insert!(%Custom{bid: nil})
    assert custom.bid
    assert TestRepo.get(Custom, custom.bid)
    assert TestRepo.delete!(custom)
    refute TestRepo.get(Custom, custom.bid)

    uuid = Ecto.UUID.generate
    assert {2, nil} = TestRepo.insert_all(Custom, [%{uuid: uuid}, %{bid: custom.bid}])
    assert [%Custom{bid: bid2, uuid: nil},
            %Custom{bid: bid1, uuid: ^uuid}] = Enum.sort_by(TestRepo.all(Custom), & &1.uuid)
    assert bid1 && bid2
    assert custom.bid != bid1
    assert custom.bid == bid2
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

  ## Query syntax

  test "query select take" do
    TestRepo.insert!(%Post{title: "1"})
    TestRepo.insert!(%Post{title: "1"})
    TestRepo.insert!(%Post{title: "2"})

    [p1, p2, p3] = Post |> select([p], take(p, [:title])) |> TestRepo.all
    refute p1.id
    assert p1.title
    refute p2.id
    assert p2.title
    refute p3.id
    assert p3.title

    [p1, p2, p3] = Post |> select([p], take(p, [:id])) |> TestRepo.all
    assert p1.id
    refute p1.title
    assert p2.id
    refute p2.title
    assert p3.id
    refute p3.title
  end

  test "query count distinct" do
    TestRepo.insert!(%Post{title: "1"})
    TestRepo.insert!(%Post{title: "1"})
    TestRepo.insert!(%Post{title: "2"})

    assert [3] == Post |> select([p], count(p.title)) |> TestRepo.all
    assert [2] == Post |> select([p], count(p.title, :distinct)) |> TestRepo.all
  end

  test "query where interpolation" do
    post1 = TestRepo.insert!(%Post{text: "x", title: "hello"  })
    post2 = TestRepo.insert!(%Post{text: "y", title: "goodbye"})

    assert [post1, post2] == Post |> where([], []) |> TestRepo.all
    assert [post1]        == Post |> where([], [title: "hello"]) |> TestRepo.all
    assert [post1]        == Post |> where([], [title: "hello", id: ^post1.id]) |> TestRepo.all

    params0 = []
    params1 = [title: "hello"]
    params2 = [title: "hello", id: post1.id]
    assert [post1, post2]  == (from Post, where: ^params0) |> TestRepo.all
    assert [post1]         == (from Post, where: ^params1) |> TestRepo.all
    assert [post1]         == (from Post, where: ^params2) |> TestRepo.all

    post3 = TestRepo.insert!(%Post{text: "y", title: "goodbye", uuid: nil})
    params3 = [title: "goodbye", uuid: post3.uuid]
    assert [post3]         == (from Post, where: ^params3) |> TestRepo.all
  end

  ## Logging

  test "log entry logged on query" do
    log = fn entry ->
      assert %Ecto.LogEntry{result: {:ok, _}} = entry
      assert is_integer(entry.query_time) and entry.query_time >= 0
      assert is_integer(entry.decode_time) and entry.query_time >= 0
      assert is_integer(entry.queue_time) and entry.queue_time >= 0
      send(self(), :logged)
    end
    Process.put(:on_log, log)

    _ = TestRepo.all(Post)
    assert_received :logged
  end

  test "log entry not logged when log is false" do
    Process.put(:on_log, fn _ -> flunk("logged") end)
    TestRepo.insert!(%Post{title: "1"}, [log: false])
  end
end
