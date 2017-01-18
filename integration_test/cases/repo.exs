Code.require_file "../support/types.exs", __DIR__

defmodule Ecto.Integration.RepoTest do
  use Ecto.Integration.Case, async: Application.get_env(:ecto, :async_integration_tests, true)

  alias Ecto.Integration.TestRepo
  import Ecto.Query

  alias Ecto.Integration.Post
  alias Ecto.Integration.User
  alias Ecto.Integration.Comment
  alias Ecto.Integration.Permalink
  alias Ecto.Integration.Custom
  alias Ecto.Integration.Barebone
  alias Ecto.Integration.CompositePk
  alias Ecto.Integration.PostUsecTimestamps
  alias Ecto.Integration.PostUserCompositePk

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

  @tag :invalid_prefix
  test "fetch with invalid prefix" do
    assert catch_error(TestRepo.all("posts", prefix: "oops"))
  end

  test "insert, update and delete" do
    post = %Post{title: "insert, update, delete", text: "fetch empty"}
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

  @tag :composite_pk
  test "insert, update and delete with composite pk" do
    c1 = TestRepo.insert!(%CompositePk{a: 1, b: 2, name: "first"})
    c2 = TestRepo.insert!(%CompositePk{a: 1, b: 3, name: "second"})

    assert CompositePk |> first |> TestRepo.one == c1
    assert CompositePk |> last |> TestRepo.one == c2

    changeset = Ecto.Changeset.cast(c1, %{name: "first change"}, ~w(name))
    c1 = TestRepo.update!(changeset)
    assert TestRepo.get_by!(CompositePk, %{a: 1, b: 2}) == c1

    TestRepo.delete!(c2)
    assert TestRepo.all(CompositePk) == [c1]

    assert_raise ArgumentError, ~r"to have exactly one primary key", fn ->
      TestRepo.get(CompositePk, [])
    end

    assert_raise ArgumentError, ~r"to have exactly one primary key", fn ->
      TestRepo.get!(CompositePk, [1, 2])
    end
  end

  @tag :composite_pk
  test "insert, update and delete with associated composite pk" do
    user = TestRepo.insert!(%User{})
    post = TestRepo.insert!(%Post{title: "post title", text: "post text"})

    user_post = TestRepo.insert!(%PostUserCompositePk{user_id: user.id, post_id: post.id})
    assert TestRepo.get_by!(PostUserCompositePk, [user_id: user.id, post_id: post.id]) == user_post
    TestRepo.delete!(user_post)
    assert TestRepo.all(PostUserCompositePk) == []
  end

  @tag :invalid_prefix
  test "insert, update and delete with invalid prefix" do
    post = TestRepo.insert!(%Post{})
    changeset = Ecto.Changeset.change(post, title: "foo")
    assert catch_error(TestRepo.insert(%Post{}, prefix: "oops"))
    assert catch_error(TestRepo.update(changeset, prefix: "oops"))
    assert catch_error(TestRepo.delete(changeset, prefix: "oops"))
  end

  test "insert and update with changeset" do
    # On insert we merge the fields and changes
    changeset = Ecto.Changeset.cast(%Post{text: "x", title: "wrong"},
                                    %{"title" => "hello", "temp" => "unknown"}, ~w(title temp))

    post = TestRepo.insert!(changeset)
    assert %Post{text: "x", title: "hello", temp: "unknown"} = post
    assert %Post{text: "x", title: "hello", temp: "temp"} = TestRepo.get!(Post, post.id)

    # On update we merge only fields, direct schema changes are discarded
    changeset = Ecto.Changeset.cast(%{post | text: "y"},
                                    %{"title" => "world", "temp" => "unknown"}, ~w(title temp))

    assert %Post{text: "y", title: "world", temp: "unknown"} = TestRepo.update!(changeset)
    assert %Post{text: "x", title: "world", temp: "temp"} = TestRepo.get!(Post, post.id)
  end

  test "insert and update with empty changeset" do
    # On insert we merge the fields and changes
    changeset = Ecto.Changeset.cast(%Permalink{}, %{}, ~w())
    assert %Permalink{} = permalink = TestRepo.insert!(changeset)

    # Assert we can update the same value twice,
    # without changes, without triggering stale errors.
    changeset = Ecto.Changeset.cast(permalink, %{}, ~w())
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

    changeset = Ecto.Changeset.cast(struct(RAW, %{}), %{}, ~w())

    # If the field is nil, we will not send it
    # and read the value back from the database.
    assert %{id: cid, lock_version: 1} = raw = TestRepo.insert!(changeset)

    # Set the counter to 11, so we can read it soon
    TestRepo.update_all from(u in RAW, where: u.id == ^cid), set: [lock_version: 11]

    # We will read back on update too
    changeset = Ecto.Changeset.cast(raw, %{"text" => "0"}, ~w(text))
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
    changeset = Ecto.Changeset.cast(%Post{id: 11}, %{"id" => "13"}, ~w(id))
    assert %Post{id: 13} = post = TestRepo.insert!(changeset)

    changeset = Ecto.Changeset.cast(post, %{"id" => "15"}, ~w(id))
    assert %Post{id: 15} = TestRepo.update!(changeset)
  end

  @tag :uses_usec
  test "insert and fetch a schema with timestamps with usec" do
    p1 = TestRepo.insert!(%PostUsecTimestamps{title: "hello"})
    assert [p1] == TestRepo.all(PostUsecTimestamps)
  end

  test "insert and fetch a schema with utc timestamps" do
    datetime = System.system_time(:seconds) * 1_000_000 |> DateTime.from_unix!(:microseconds)
    TestRepo.insert!(%User{inserted_at: datetime})
    assert [%{inserted_at: ^datetime}] = TestRepo.all(User)
  end

  test "optimistic locking in update/delete operations" do
    import Ecto.Changeset, only: [cast: 3, optimistic_lock: 2]
    base_post = TestRepo.insert!(%Comment{})

    cs_ok =
      base_post
      |> cast(%{"text" => "foo.bar"}, ~w(text))
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
      assert_raise Ecto.ConstraintError, ~r/constraint error when attempting to insert struct/, fn ->
        changeset
        |> TestRepo.insert()
      end

    assert exception.message =~ "unique: posts_uuid_index"
    assert exception.message =~ "The changeset has not defined any constraint."

    message = ~r/constraint error when attempting to insert struct/
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
    assert changeset.errors == [uuid: {"has already been taken", []}]
    assert changeset.data.__meta__.state == :built
  end

  @tag :unique_constraint
  test "unique constraint from association" do
    uuid = Ecto.UUID.generate()
    post = & %Post{} |> Ecto.Changeset.change(uuid: &1) |> Ecto.Changeset.unique_constraint(:uuid)

    {:error, changeset} =
      TestRepo.insert %User{
        comments: [%Comment{}],
        permalink: %Permalink{},
        posts: [post.(uuid), post.(uuid), post.(Ecto.UUID.generate)]
      }

    [_, p2, _] = changeset.changes.posts
    assert p2.errors == [uuid: {"has already been taken", []}]
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
    assert changeset.errors == [uuid: {"has already been taken", []}]
    assert changeset.data.__meta__.state == :built
  end

  test "unique pseudo-constraint violation error message with join table at the repository" do
    post =
      TestRepo.insert!(%Post{title: "some post"})
      |> TestRepo.preload(:unique_users)

    user =
      TestRepo.insert!(%User{name: "some user"})

    # Violate the unique composite index
    {:error, changeset} =
      post
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:unique_users, [user, user])
      |> TestRepo.update

    errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
    assert errors == %{unique_users: [%{}, %{id: ["has already been taken"]}]}
    refute changeset.valid?
  end

  @tag :join
  @tag :unique_constraint
  test "unique constraint violation error message with join table in single changeset" do
    post =
      TestRepo.insert!(%Post{title: "some post"})
      |> TestRepo.preload(:constraint_users)

    user =
      TestRepo.insert!(%User{name: "some user"})

    # Violate the unique composite index
    {:error, changeset} =
      post
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:constraint_users, [user, user])
      |> Ecto.Changeset.unique_constraint(:user,
          name: :posts_users_composite_pk_post_id_user_id_index,
          message: "has already been assigned")
      |> TestRepo.update

    errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
    assert errors == %{constraint_users: [%{}, %{user: ["has already been assigned"]}]}

    refute changeset.valid?
  end

  @tag :join
  @tag :unique_constraint
  test "unique constraint violation error message with join table and separate changesets" do
    post =
      TestRepo.insert!(%Post{title: "some post"})
      |> TestRepo.preload(:constraint_users)

    user = TestRepo.insert!(%User{name: "some user"})

    post
    |> Ecto.Changeset.change
    |> Ecto.Changeset.put_assoc(:constraint_users, [user])
    |> TestRepo.update

    # Violate the unique composite index
    {:error, changeset} =
      post
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:constraint_users, [user])
      |> Ecto.Changeset.unique_constraint(:user,
          name: :posts_users_composite_pk_post_id_user_id_index,
          message: "has already been assigned")
      |> TestRepo.update

    errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
    assert errors == %{constraint_users: [%{user: ["has already been assigned"]}]}

    refute changeset.valid?
  end

  @tag :foreign_key_constraint
  test "foreign key constraint" do
    changeset = Ecto.Changeset.change(%Comment{post_id: 0})

    exception =
      assert_raise Ecto.ConstraintError, ~r/constraint error when attempting to insert struct/, fn ->
        changeset
        |> TestRepo.insert()
      end

    assert exception.message =~ "foreign_key: comments_post_id_fkey"
    assert exception.message =~ "The changeset has not defined any constraint."

    message = ~r/constraint error when attempting to insert struct/
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
    assert changeset.errors == [post_id: {"does not exist", []}]
  end

  @tag :foreign_key_constraint
  test "assoc constraint" do
    changeset = Ecto.Changeset.change(%Comment{post_id: 0})

    exception =
      assert_raise Ecto.ConstraintError, ~r/constraint error when attempting to insert struct/, fn ->
        changeset
        |> TestRepo.insert()
      end

    assert exception.message =~ "foreign_key: comments_post_id_fkey"
    assert exception.message =~ "The changeset has not defined any constraint."

    message = ~r/constraint error when attempting to insert struct/
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
    assert changeset.errors == [post: {"does not exist", []}]
  end

  @tag :foreign_key_constraint
  test "no assoc constraint error" do
    user = TestRepo.insert!(%User{})
    TestRepo.insert!(%Permalink{user_id: user.id})

    exception =
      assert_raise Ecto.ConstraintError, ~r/constraint error when attempting to delete struct/, fn ->
        TestRepo.delete!(user)
      end

    assert exception.message =~ "foreign_key: permalinks_user_id_fkey"
    assert exception.message =~ "The changeset has not defined any constraint."
  end

  @tag :foreign_key_constraint
  test "no assoc constraint with changeset mismatch" do
    user = TestRepo.insert!(%User{})
    TestRepo.insert!(%Permalink{user_id: user.id})

    message = ~r/constraint error when attempting to delete struct/
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
    assert changeset.errors == [permalink: {"is still associated with this entry", []}]
  end

  test "insert and update with failing child foreign key" do
    defmodule Order do
      use Ecto.Integration.Schema
      import Ecto.Changeset

      schema "orders" do
        embeds_one :item, Ecto.Integration.Item
        belongs_to :comment, Ecto.Integration.Comment
      end

      def changeset(order, params) do
        order
        |> cast(params, [:comment_id])
        |> cast_embed(:item, with: &item_changeset/2)
        |> cast_assoc(:comment, with: &comment_changeset/2)
      end

      def item_changeset(item, params) do
        item
        |> cast(params, [:price])
      end

      def comment_changeset(comment, params) do
        comment
        |> cast(params, [:post_id, :text])
        |> cast_assoc(:post)
        |> assoc_constraint(:post)
      end
    end

    changeset = Order.changeset(struct(Order, %{}), %{item: %{price: 10}, comment: %{text: "1", post_id: 0}})

    assert %Ecto.Changeset{} = changeset.changes.item

    {:error, changeset} = TestRepo.insert(changeset)
    assert %Ecto.Changeset{} = changeset.changes.item

    order = TestRepo.insert!(Order.changeset(struct(Order, %{}), %{}))
    |> TestRepo.preload([:comment])

    changeset = Order.changeset(order, %{item: %{price: 10}, comment: %{text: "1", post_id: 0}})

    assert %Ecto.Changeset{} = changeset.changes.item

    {:error, changeset} = TestRepo.update(changeset)
    assert %Ecto.Changeset{} = changeset.changes.item
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

  test "get(!) with binary_id" do
    custom = TestRepo.insert!(%Custom{})
    bid = custom.bid
    assert %Custom{bid: ^bid} = TestRepo.get(Custom, bid)
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

  test "first, last and one(!)" do
    post1 = TestRepo.insert!(%Post{title: "1", text: "hai"})
    post2 = TestRepo.insert!(%Post{title: "2", text: "hai"})

    assert post1 == Post |> first |> TestRepo.one
    assert post2 == Post |> last |> TestRepo.one

    query = from p in Post, order_by: p.title
    assert post1 == query |> first |> TestRepo.one
    assert post2 == query |> last |> TestRepo.one

    query = from p in Post, order_by: [desc: p.title], limit: 10
    assert post2 == query |> first |> TestRepo.one
    assert post1 == query |> last |> TestRepo.one

    query = from p in Post, where: is_nil(p.id)
    refute query |> first |> TestRepo.one
    refute query |> first |> TestRepo.one
    assert_raise Ecto.NoResultsError, fn -> query |> first |> TestRepo.one! end
    assert_raise Ecto.NoResultsError, fn -> query |> last |> TestRepo.one! end
  end

  test "aggregate" do
    assert TestRepo.aggregate(Post, :max, :visits) == nil

    TestRepo.insert!(%Post{visits: 10})
    TestRepo.insert!(%Post{visits: 12})
    TestRepo.insert!(%Post{visits: 14})
    TestRepo.insert!(%Post{visits: 14})

    # Barebones
    assert TestRepo.aggregate(Post, :max, :visits) == 14
    assert TestRepo.aggregate(Post, :min, :visits) == 10
    assert TestRepo.aggregate(Post, :count, :visits) == 4
    assert "50" = to_string(TestRepo.aggregate(Post, :sum, :visits))
    assert "12.5" <> _ = to_string(TestRepo.aggregate(Post, :avg, :visits))

    # With order_by
    query = from Post, order_by: [asc: :visits]
    assert TestRepo.aggregate(query, :max, :visits) == 14

    # With order_by and limit
    query = from Post, order_by: [asc: :visits], limit: 2
    assert TestRepo.aggregate(query, :max, :visits) == 12

    # With distinct
    query = from Post, order_by: [asc: :visits], distinct: true
    assert TestRepo.aggregate(query, :count, :visits) == 3
  end

  test "insert all" do
    assert {2, nil} = TestRepo.insert_all("comments", [[text: "1"], %{text: "2", lock_version: 2}])
    assert {2, nil} = TestRepo.insert_all({"comments", Comment}, [[text: "3"], %{text: "4", lock_version: 2}])
    assert [%Comment{text: "1", lock_version: 1},
            %Comment{text: "2", lock_version: 2},
            %Comment{text: "3", lock_version: 1},
            %Comment{text: "4", lock_version: 2}] = TestRepo.all(Comment)

    assert {2, nil} = TestRepo.insert_all(Post, [[], []])
    assert [%Post{}, %Post{}] = TestRepo.all(Post)

    assert {0, nil} = TestRepo.insert_all("posts", [])
    assert {0, nil} = TestRepo.insert_all({"posts", Post}, [])
  end

  @tag :invalid_prefix
  test "insert all with invalid prefix" do
    assert catch_error(TestRepo.insert_all(Post, [[], []], prefix: "oops"))
  end

  @tag :returning
  test "insert all with returning with schema" do
    assert {0, []} = TestRepo.insert_all(Comment, [], returning: true)
    assert {0, nil} = TestRepo.insert_all(Comment, [], returning: false)

    {2, [c1, c2]} = TestRepo.insert_all(Comment, [[text: "1"], [text: "2"]], returning: [:id, :text])
    assert %Comment{text: "1", __meta__: %{state: :loaded}} = c1
    assert %Comment{text: "2", __meta__: %{state: :loaded}} = c2

    {2, [c1, c2]} = TestRepo.insert_all(Comment, [[text: "3"], [text: "4"]], returning: true)
    assert %Comment{text: "3", __meta__: %{state: :loaded}} = c1
    assert %Comment{text: "4", __meta__: %{state: :loaded}} = c2
  end

  @tag :returning
  test "insert all with returning without schema" do
    {2, [c1, c2]} = TestRepo.insert_all("comments", [[text: "1"], [text: "2"]], returning: [:id, :text])
    assert %{id: _, text: "1"} = c1
    assert %{id: _, text: "2"} = c2

    assert_raise ArgumentError, fn ->
      TestRepo.insert_all("comments", [[text: "1"], [text: "2"]], returning: true)
    end
  end

  test "insert all with dumping" do
    datetime = ~N[2014-01-16 20:26:51.000000]
    assert {2, nil} = TestRepo.insert_all(Post, [%{inserted_at: datetime}, %{title: "date"}])
    assert [%Post{inserted_at: ^datetime, title: nil},
            %Post{inserted_at: nil, title: "date"}] = TestRepo.all(Post)
  end

  test "insert all autogenerates for binary_id type" do
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

    assert {3, nil} = TestRepo.update_all("posts", [set: [title: nil]], returning: false)

    assert %Post{title: nil} = TestRepo.get(Post, id1)
    assert %Post{title: nil} = TestRepo.get(Post, id2)
    assert %Post{title: nil} = TestRepo.get(Post, id3)
  end

  @tag :invalid_prefix
  test "update all with invalid prefix" do
    assert catch_error(TestRepo.update_all(Post, [set: [title: "x"]], prefix: "oops"))
  end

  @tag :returning
  test "update all with returning with schema" do
    assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1"})
    assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2"})
    assert %Post{id: id3} = TestRepo.insert!(%Post{title: "3"})

    assert {3, posts} = TestRepo.update_all(Post, [set: [title: "x"]], returning: true)

    [p1, p2, p3] = Enum.sort_by(posts, & &1.id)
    assert %Post{id: ^id1, title: "x"} = p1
    assert %Post{id: ^id2, title: "x"} = p2
    assert %Post{id: ^id3, title: "x"} = p3

    assert {3, posts} = TestRepo.update_all(Post, [set: [visits: 11]], returning: [:id, :visits])

    [p1, p2, p3] = Enum.sort_by(posts, & &1.id)
    assert %Post{id: ^id1, title: nil, visits: 11} = p1
    assert %Post{id: ^id2, title: nil, visits: 11} = p2
    assert %Post{id: ^id3, title: nil, visits: 11} = p3
  end

  @tag :returning
  test "update all with returning without schema" do
    assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1"})
    assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2"})
    assert %Post{id: id3} = TestRepo.insert!(%Post{title: "3"})

    assert {3, posts} = TestRepo.update_all("posts", [set: [title: "x"]], returning: [:id, :title])

    [p1, p2, p3] = Enum.sort_by(posts, & &1.id)
    assert p1 == %{id: id1, title: "x"}
    assert p2 == %{id: id2, title: "x"}
    assert p3 == %{id: id3, title: "x"}
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
    datetime = ~N[2014-01-16 20:26:51.000000]
    assert %Post{id: id} = TestRepo.insert!(%Post{})

    assert {1, nil} = TestRepo.update_all(Post, set: [text: text, inserted_at: datetime])
    assert %Post{text: "hai", inserted_at: ^datetime} = TestRepo.get(Post, id)
  end

  test "delete all" do
    assert %Post{} = TestRepo.insert!(%Post{title: "1", text: "hai"})
    assert %Post{} = TestRepo.insert!(%Post{title: "2", text: "hai"})
    assert %Post{} = TestRepo.insert!(%Post{title: "3", text: "hai"})

    assert {3, nil} = TestRepo.delete_all(Post, returning: false)
    assert [] = TestRepo.all(Post)
  end

  @tag :invalid_prefix
  test "delete all with invalid prefix" do
    assert catch_error(TestRepo.delete_all(Post, prefix: "oops"))
  end

  @tag :returning
  test "delete all with returning with schema" do
    assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1", text: "hai"})
    assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2", text: "hai"})
    assert %Post{id: id3} = TestRepo.insert!(%Post{title: "3", text: "hai"})

    assert {3, posts} = TestRepo.delete_all(Post, returning: true)

    [p1, p2, p3] = Enum.sort_by(posts, & &1.id)
    assert %Post{id: ^id1, title: "1"} = p1
    assert %Post{id: ^id2, title: "2"} = p2
    assert %Post{id: ^id3, title: "3"} = p3
  end

  @tag :returning
  test "delete all with returning without schema" do
    assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1", text: "hai"})
    assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2", text: "hai"})
    assert %Post{id: id3} = TestRepo.insert!(%Post{title: "3", text: "hai"})

    assert {3, posts} = TestRepo.delete_all("posts", returning: [:id, :title])

    [p1, p2, p3] = Enum.sort_by(posts, & &1.id)
    assert p1 == %{id: id1, title: "1"}
    assert p2 == %{id: id2, title: "2"}
    assert p3 == %{id: id3, title: "3"}
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

  test "query select expressions" do
    %Post{} = TestRepo.insert!(%Post{title: "1", text: "hai"})

    assert [{"1", "hai"}] ==
           TestRepo.all(from p in Post, select: {p.title, p.text})

    assert [["1", "hai"]] ==
           TestRepo.all(from p in Post, select: [p.title, p.text])

    assert [%{:title => "1", 3 => "hai", "text" => "hai"}] ==
           TestRepo.all(from p in Post, select: %{
             :title => p.title,
             "text" => p.text,
             3 => p.text
           })

    assert [%{:title => "1", "1" => "hai", "text" => "hai"}] ==
           TestRepo.all(from p in Post, select: %{
             :title  => p.title,
             p.title => p.text,
             "text"  => p.text
           })
  end

  test "query select map update" do
    %Post{} = TestRepo.insert!(%Post{title: "1", text: "hai"})

    assert [%Post{:title => "new title", text: "hai"}] =
           TestRepo.all(from p in Post, select: %{p | title: "new title"})

    assert_raise KeyError, fn ->
      TestRepo.all(from p in Post, select: %{p | unknown: "new title"})
    end

    assert_raise BadMapError, fn ->
      TestRepo.all(from p in Post, select: %{p.title | title: "new title"})
    end
  end

  test "query select take with structs" do
    %{id: pid1} = TestRepo.insert!(%Post{title: "1"})
    %{id: pid2} = TestRepo.insert!(%Post{title: "2"})
    %{id: pid3} = TestRepo.insert!(%Post{title: "3"})

    [p1, p2, p3] = Post |> select([p], struct(p, [:title])) |> order_by([:title]) |> TestRepo.all
    refute p1.id
    assert p1.title == "1"
    assert match?(%Post{}, p1)
    refute p2.id
    assert p2.title == "2"
    assert match?(%Post{}, p2)
    refute p3.id
    assert p3.title == "3"
    assert match?(%Post{}, p3)

    [p1, p2, p3] = Post |> select([:id]) |> order_by([:id]) |> TestRepo.all
    assert %Post{id: ^pid1} = p1
    assert %Post{id: ^pid2} = p2
    assert %Post{id: ^pid3} = p3
  end

  test "query select take with maps" do
    %{id: pid1} = TestRepo.insert!(%Post{title: "1"})
    %{id: pid2} = TestRepo.insert!(%Post{title: "2"})
    %{id: pid3} = TestRepo.insert!(%Post{title: "3"})

    [p1, p2, p3] = "posts" |> select([p], map(p, [:title])) |> order_by([:title]) |> TestRepo.all
    assert p1 == %{title: "1"}
    assert p2 == %{title: "2"}
    assert p3 == %{title: "3"}

    [p1, p2, p3] = "posts" |> select([:id]) |> order_by([:id]) |> TestRepo.all
    assert p1 == %{id: pid1}
    assert p2 == %{id: pid2}
    assert p3 == %{id: pid3}
  end

  test "query select take with assocs" do
    %{id: pid} = TestRepo.insert!(%Post{title: "post"})
    TestRepo.insert!(%Comment{post_id: pid, text: "comment"})

    fields = [:id, :title, comments: [:text, :post_id]]

    [p] = Post |> preload(:comments) |> select([p], ^fields) |> TestRepo.all
    assert match?(%Post{title: "post"}, p)
    assert match?([%Comment{text: "comment"}], p.comments)

    [p] = Post |> preload(:comments) |> select([p], struct(p, ^fields)) |> TestRepo.all
    assert match?(%Post{title: "post"}, p)
    assert match?([%Comment{text: "comment"}], p.comments)

    [p] = Post |> preload(:comments) |> select([p], map(p, ^fields)) |> TestRepo.all
    assert p == %{id: pid, title: "post", comments: [%{text: "comment", post_id: pid}]}
  end

  test "query count distinct" do
    TestRepo.insert!(%Post{title: "1"})
    TestRepo.insert!(%Post{title: "1"})
    TestRepo.insert!(%Post{title: "2"})

    assert [3] == Post |> select([p], count(p.title)) |> TestRepo.all
    assert [2] == Post |> select([p], count(p.title, :distinct)) |> TestRepo.all
  end

  test "query where interpolation" do
    post1 = TestRepo.insert!(%Post{text: "x", title: "hello"})
    post2 = TestRepo.insert!(%Post{text: "y", title: "goodbye"})

    assert [post1, post2] == Post |> where([], []) |> TestRepo.all |> Enum.sort_by(& &1.id)
    assert [post1]        == Post |> where([], [title: "hello"]) |> TestRepo.all
    assert [post1]        == Post |> where([], [title: "hello", id: ^post1.id]) |> TestRepo.all

    params0 = []
    params1 = [title: "hello"]
    params2 = [title: "hello", id: post1.id]
    assert [post1, post2]  == (from Post, where: ^params0) |> TestRepo.all |> Enum.sort_by(& &1.id)
    assert [post1]         == (from Post, where: ^params1) |> TestRepo.all
    assert [post1]         == (from Post, where: ^params2) |> TestRepo.all

    post3 = TestRepo.insert!(%Post{text: "y", title: "goodbye", uuid: nil})
    params3 = [title: "goodbye", uuid: post3.uuid]
    assert [post3] == (from Post, where: ^params3) |> TestRepo.all
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

  test "load" do
    inserted_at = ~N[2016-01-01 09:00:00.000000]
    TestRepo.insert!(%Post{title: "title1", inserted_at: inserted_at, public: false})

    result = Ecto.Adapters.SQL.query!(TestRepo, "SELECT * FROM posts", [])
    posts = Enum.map(result.rows, &TestRepo.load(Post, {result.columns, &1}))
    assert [%Post{title: "title1", inserted_at: ^inserted_at, public: false}] = posts
  end

  describe "upsert via insert" do
    @describetag :upsert

    test "on conflict raise" do
      {:ok, inserted} = TestRepo.insert(%Post{title: "first"}, on_conflict: :raise)
      assert catch_error(TestRepo.insert(%Post{id: inserted.id, title: "second"}, on_conflict: :raise))
    end

    test "on conflict ignore" do
      post = %Post{title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"}
      {:ok, inserted} = TestRepo.insert(post, on_conflict: :nothing)
      assert inserted.id
      assert inserted.__meta__.state == :loaded

      {:ok, not_inserted} = TestRepo.insert(post, on_conflict: :nothing)
      assert not_inserted.id == nil
      assert not_inserted.__meta__.state == :loaded
    end

    @tag :with_conflict_target
    test "on conflict and associations" do
      on_conflict = [set: [title: "second"]]
      post = %Post{uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e",
                   title: "first", comments: [%Comment{}]}
      {:ok, inserted} = TestRepo.insert(post, on_conflict: on_conflict, conflict_target: [:uuid])
      assert inserted.id
    end

    @tag :with_conflict_target
    test "on conflict with inc" do
      uuid = "6fa459ea-ee8a-3ca4-894e-db77e160355e"
      post = %Post{title: "first", uuid: uuid}
      {:ok, _} = TestRepo.insert(post)
      post = %{title: "upsert", uuid: uuid}
      TestRepo.insert_all(Post, [post], on_conflict: [inc: [visits: 1]], conflict_target: :uuid)
    end

    @tag :with_conflict_target
    test "on conflict ignore and conflict target" do
      post = %Post{title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"}
      {:ok, inserted} = TestRepo.insert(post, on_conflict: :nothing, conflict_target: [:uuid])
      assert inserted.id

      # Error on non-conflict target
      assert catch_error(TestRepo.insert(post, on_conflict: :nothing, conflict_target: [:id]))

      # Error on conflict target
      {:ok, not_inserted} = TestRepo.insert(post, on_conflict: :nothing, conflict_target: [:uuid])
      assert not_inserted.id == nil
    end

    @tag :without_conflict_target
    test "on conflict keyword list" do
      on_conflict = [set: [title: "second"]]
      post = %Post{title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"}
      {:ok, inserted} = TestRepo.insert(post, on_conflict: on_conflict)
      assert inserted.id

      {:ok, updated} = TestRepo.insert(post, on_conflict: on_conflict)
      assert updated.id == inserted.id
      assert updated.title != "second"
      assert TestRepo.get!(Post, inserted.id).title == "second"
    end

    @tag :with_conflict_target
    test "on conflict keyword list and conflict target" do
      on_conflict = [set: [title: "second"]]
      post = %Post{title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"}
      {:ok, inserted} = TestRepo.insert(post, on_conflict: on_conflict, conflict_target: [:uuid])
      assert inserted.id

      # Error on non-conflict target
      assert catch_error(TestRepo.insert(post, on_conflict: on_conflict, conflict_target: [:id]))

      {:ok, updated} = TestRepo.insert(post, on_conflict: on_conflict, conflict_target: [:uuid])
      assert updated.id == inserted.id
      assert updated.title != "second"
      assert TestRepo.get!(Post, inserted.id).title == "second"
    end

    @tag :without_conflict_target
    test "on conflict query" do
      on_conflict = from Post, update: [set: [title: "second"]]
      post = %Post{title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"}
      {:ok, inserted} = TestRepo.insert(post, on_conflict: on_conflict)
      assert inserted.id

      {:ok, updated} = TestRepo.insert(post, on_conflict: on_conflict)
      assert updated.id == inserted.id
      assert updated.title != "second"
      assert TestRepo.get!(Post, inserted.id).title == "second"
    end

    @tag :with_conflict_target
    test "on conflict query and conflict target" do
      on_conflict = from Post, update: [set: [title: "second"]]
      post = %Post{title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"}
      {:ok, inserted} = TestRepo.insert(post, on_conflict: on_conflict, conflict_target: [:uuid])
      assert inserted.id

      # Error on non-conflict target
      assert catch_error(TestRepo.insert(post, on_conflict: on_conflict, conflict_target: [:id]))

      {:ok, updated} = TestRepo.insert(post, on_conflict: on_conflict, conflict_target: [:uuid])
      assert updated.id == inserted.id
      assert updated.title != "second"
      assert TestRepo.get!(Post, inserted.id).title == "second"
    end

    @tag :without_conflict_target
    test "on conflict replace_all" do
      post = %Post{title: "first", text: "text", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"}
      {:ok, inserted} = TestRepo.insert(post, on_conflict: :replace_all)
      assert inserted.id

      # Error on non-conflict target
      post = %Post{id: inserted.id, title: "updated",
                   text: "updated", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"}

      # Error on conflict target
      post = TestRepo.insert!(post, on_conflict: :replace_all)
      assert post.title == "updated"
      assert post.text == "updated"

      assert TestRepo.all(from p in Post, select: p.title) == ["updated"]
      assert TestRepo.all(from p in Post, select: p.text) == ["updated"]
      assert TestRepo.all(from p in Post, select: count(p.id)) == [1]
    end

    @tag :with_conflict_target
    test "on conflict replace_all and conflict target" do
      post = %Post{title: "first", text: "text", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"}
      {:ok, inserted} = TestRepo.insert(post, on_conflict: :replace_all, conflict_target: :id)
      assert inserted.id

      # Error on non-conflict target
      post = %Post{id: inserted.id, title: "updated",
                   text: "updated", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"}

      # Error on conflict target
      post = TestRepo.insert!(post, on_conflict: :replace_all, conflict_target: :id)
      assert post.title == "updated"
      assert post.text == "updated"

      assert TestRepo.all(from p in Post, select: p.title) == ["updated"]
      assert TestRepo.all(from p in Post, select: p.text) == ["updated"]
      assert TestRepo.all(from p in Post, select: count(p.id)) == [1]
    end
  end

  describe "upsert via insert_all" do
    @describetag :upsert_all

    test "on conflict raise" do
      post = [title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"]
      {1, nil} = TestRepo.insert_all(Post, [post], on_conflict: :raise)
      assert catch_error(TestRepo.insert_all(Post, [post], on_conflict: :raise))
    end

    test "on conflict ignore" do
      post = [title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"]
      assert TestRepo.insert_all(Post, [post], on_conflict: :nothing) == {1, nil}

      # PG returns 0, MySQL returns 1
      {entries, nil} = TestRepo.insert_all(Post, [post], on_conflict: :nothing)
      assert entries == 0 or entries == 1

      assert length(TestRepo.all(Post)) == 1
    end

    @tag :with_conflict_target
    test "on conflict ignore and conflict target" do
      post = [title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"]
      assert TestRepo.insert_all(Post, [post], on_conflict: :nothing, conflict_target: [:uuid]) ==
             {1, nil}

      # Error on non-conflict target
      assert catch_error(TestRepo.insert_all(Post, [post], on_conflict: :nothing, conflict_target: [:id]))

      # Error on conflict target
      assert TestRepo.insert_all(Post, [post], on_conflict: :nothing, conflict_target: [:uuid]) ==
             {0, nil}
    end

    @tag :with_conflict_target
    test "on conflict keyword list and conflict target" do
      on_conflict = [set: [title: "second"]]
      post = [title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"]
      {1, nil} = TestRepo.insert_all(Post, [post], on_conflict: on_conflict, conflict_target: [:uuid])

      # Error on non-conflict target
      assert catch_error(TestRepo.insert_all(Post, [post], on_conflict: on_conflict, conflict_target: [:id]))

      # Error on conflict target
      assert TestRepo.insert_all(Post, [post], on_conflict: on_conflict, conflict_target: [:uuid]) ==
             {1, nil}
      assert TestRepo.all(from p in Post, select: p.title) == ["second"]
    end

    @tag :with_conflict_target
    test "on conflict query and conflict target" do
      on_conflict = from Post, update: [set: [title: "second"]]
      post = [title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"]
      assert TestRepo.insert_all(Post, [post], on_conflict: on_conflict, conflict_target: [:uuid]) ==
             {1, nil}

      # Error on non-conflict target
      assert catch_error(TestRepo.insert_all(Post, [post], on_conflict: on_conflict, conflict_target: [:id]))

      # Error on conflict target
      assert TestRepo.insert_all(Post, [post], on_conflict: on_conflict, conflict_target: [:uuid]) ==
             {1, nil}
      assert TestRepo.all(from p in Post, select: p.title) == ["second"]
    end

    @tag :returning
    @tag :with_conflict_target
    test "on conflict query and conflict target and returning" do
      on_conflict = from Post, update: [set: [title: "second"]]
      post = [title: "first", uuid: "6fa459ea-ee8a-3ca4-894e-db77e160355e"]
      {1, [%{id: id}]} = TestRepo.insert_all(Post, [post], on_conflict: on_conflict,
                                            conflict_target: [:uuid], returning: [:id])

      # Error on non-conflict target
      assert catch_error(TestRepo.insert_all(Post, [post], on_conflict: on_conflict,
                                             conflict_target: [:id], returning: [:id]))

      # Error on conflict target
      {1, [%Post{id: ^id, title: "second"}]} =
        TestRepo.insert_all(Post, [post], on_conflict: on_conflict,
                            conflict_target: [:uuid], returning: [:id, :title])
    end

    @tag :with_conflict_target
    test "source (without an ecto schema) on conflict query and conflict target" do
      on_conflict = [set: [title: "second"]]
      {:ok, uuid} = Ecto.UUID.dump("6fa459ea-ee8a-3ca4-894e-db77e160355e")
      post = [title: "first", uuid: uuid]
      assert TestRepo.insert_all("posts", [post], on_conflict: on_conflict, conflict_target: [:uuid]) ==
             {1, nil}

      # Error on non-conflict target
      assert catch_error(TestRepo.insert_all("posts", [post], on_conflict: on_conflict, conflict_target: [:id]))

      # Error on conflict target
      assert TestRepo.insert_all("posts", [post], on_conflict: on_conflict, conflict_target: [:uuid]) ==
             {1, nil}
      assert TestRepo.all(from p in Post, select: p.title) == ["second"]
    end

    @tag :without_conflict_target
    test "on conflict replace_all" do
      post_first = %Post{title: "first", public: true}
      post_second = %Post{title: "second", public: false}

      {:ok, inserted_first} = TestRepo.insert(post_first, on_conflict: :replace_all)
      {:ok, inserted_second} = TestRepo.insert(post_second, on_conflict: :replace_all)

      assert inserted_first.id
      assert inserted_second.id
      assert TestRepo.all(from p in Post, select: count(p.id)) == [2]

      # multiple record change value
      changes = [%{id: inserted_first.id, title: "first_updated", text: "first_updated"},
                 %{id: inserted_second.id, title: "second_updated", text: "second_updated"}]

      TestRepo.insert_all(Post, changes, on_conflict: :replace_all)

      assert TestRepo.all(from p in Post, select: count(p.id)) == [2]

      updated_first =  TestRepo.get(Post, inserted_first.id)
      assert updated_first.title == "first_updated"
      assert updated_first.text == "first_updated"

      updated_first =  TestRepo.get(Post, inserted_second.id)
      assert updated_first.title == "second_updated"
      assert updated_first.text == "second_updated"
    end

    @tag :with_conflict_target
    test "on conflict replace_all and conflict_target" do
      post_first = %Post{title: "first", public: true}
      post_second = %Post{title: "second", public: false}

      {:ok, inserted_first} = TestRepo.insert(post_first, on_conflict: :replace_all,conflict_target: :id)
      {:ok, inserted_second} = TestRepo.insert(post_second, on_conflict: :replace_all,conflict_target: :id)

      assert inserted_first.id
      assert inserted_second.id
      assert TestRepo.all(from p in Post, select: count(p.id)) == [2]

      # multiple record change value
      changes = [%{id: inserted_first.id, title: "first_updated", text: "first_updated"},
                 %{id: inserted_second.id, title: "second_updated", text: "second_updated"}]

      TestRepo.insert_all(Post, changes, on_conflict: :replace_all,conflict_target: :id)

      assert TestRepo.all(from p in Post, select: count(p.id)) == [2]

      updated_first =  TestRepo.get(Post, inserted_first.id)
      assert updated_first.title == "first_updated"
      assert updated_first.text == "first_updated"


      updated_first =  TestRepo.get(Post, inserted_second.id)
      assert updated_first.title == "second_updated"
      assert updated_first.text == "second_updated"
    end
  end
end
