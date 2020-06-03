defmodule Ecto.Integration.RepoTest do
  use Ecto.Integration.Case, async: Application.get_env(:ecto, :async_integration_tests, true)

  alias Ecto.Integration.TestRepo
  import Ecto.Query

  alias Ecto.Integration.Post
  alias Ecto.Integration.Order
  alias Ecto.Integration.User
  alias Ecto.Integration.Comment
  alias Ecto.Integration.Permalink
  alias Ecto.Integration.Custom
  alias Ecto.Integration.Barebone
  alias Ecto.Integration.CompositePk
  alias Ecto.Integration.PostUserCompositePk

  test "returns already started for started repos" do
    assert {:error, {:already_started, _}} = TestRepo.start_link()
  end

  test "supports unnamed repos" do
    assert {:ok, pid} = TestRepo.start_link(name: nil)
    assert Ecto.Repo.Queryable.all(pid, Post, []) == []
  end

  test "all empty" do
    assert TestRepo.all(Post) == []
    assert TestRepo.all(from p in Post) == []
  end

  test "all with in" do
    TestRepo.insert!(%Post{title: "hello"})

    # Works without the query cache.
    assert_raise Ecto.Query.CastError, fn ->
      TestRepo.all(from p in Post, where: p.title in ^nil)
    end

    assert [] = TestRepo.all from p in Post, where: p.title in []
    assert [] = TestRepo.all from p in Post, where: p.title in ["1", "2", "3"]
    assert [] = TestRepo.all from p in Post, where: p.title in ^[]

    assert [_] = TestRepo.all from p in Post, where: p.title not in []
    assert [_] = TestRepo.all from p in Post, where: p.title in ["1", "hello", "3"]
    assert [_] = TestRepo.all from p in Post, where: p.title in ["1", ^"hello", "3"]
    assert [_] = TestRepo.all from p in Post, where: p.title in ^["1", "hello", "3"]

    # Still doesn't work after the query cache.
    assert_raise Ecto.Query.CastError, fn ->
      TestRepo.all(from p in Post, where: p.title in ^nil)
    end
  end

  test "all using named from" do
    TestRepo.insert!(%Post{title: "hello"})

    query =
      from(p in Post, as: :post)
      |> where([post: p], p.title == "hello")

    assert [_] = TestRepo.all query
  end

  test "all without schema" do
    %Post{} = TestRepo.insert!(%Post{title: "title1"})
    %Post{} = TestRepo.insert!(%Post{title: "title2"})

    assert ["title1", "title2"] =
      TestRepo.all(from(p in "posts", order_by: p.title, select: p.title))

    assert [_] =
      TestRepo.all(from(p in "posts", where: p.title == "title1", select: p.id))
  end

  test "all shares metadata" do
    TestRepo.insert!(%Post{title: "title1"})
    TestRepo.insert!(%Post{title: "title2"})

    [post1, post2] = TestRepo.all(Post)
    assert :erts_debug.same(post1.__meta__, post2.__meta__)

    [new_post1, new_post2] = TestRepo.all(Post)
    assert :erts_debug.same(post1.__meta__, new_post1.__meta__)
    assert :erts_debug.same(post2.__meta__, new_post2.__meta__)
  end

  @tag :invalid_prefix
  test "all with invalid prefix" do
    assert catch_error(TestRepo.all("posts", prefix: "oops"))
  end

  test "insert, update and delete" do
    post = %Post{title: "insert, update, delete", visits: 1}
    meta = post.__meta__

    assert %Post{} = inserted = TestRepo.insert!(post)
    assert %Post{} = updated = TestRepo.update!(Ecto.Changeset.change(inserted, visits: 2))

    deleted_meta = put_in meta.state, :deleted
    assert %Post{__meta__: ^deleted_meta} = TestRepo.delete!(updated)

    loaded_meta = put_in meta.state, :loaded
    assert %Post{__meta__: ^loaded_meta} = TestRepo.insert!(post)

    post = TestRepo.one(Post)
    assert post.__meta__.state == :loaded
    assert post.inserted_at
  end

  test "insert, update and delete with field source" do
    permalink = %Permalink{url: "url"}
    assert %Permalink{url: "url"} = inserted =
           TestRepo.insert!(permalink)
    assert %Permalink{url: "new"} = updated =
           TestRepo.update!(Ecto.Changeset.change(inserted, url: "new"))
    assert %Permalink{url: "new"} =
           TestRepo.delete!(updated)
  end

  @tag :composite_pk
  test "insert, update and delete with composite pk" do
    c1 = TestRepo.insert!(%CompositePk{a: 1, b: 2, name: "first"})
    c2 = TestRepo.insert!(%CompositePk{a: 1, b: 3, name: "second"})

    assert CompositePk |> first |> TestRepo.one == c1
    assert CompositePk |> last |> TestRepo.one == c2

    changeset = Ecto.Changeset.cast(c1, %{name: "first change"}, ~w(name)a)
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
    post = TestRepo.insert!(%Post{title: "post title"})

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

    # Check we can still insert the post after the invalid prefix attempt
    assert %Post{id: _} = TestRepo.insert!(%Post{})
  end

  test "insert and update with changeset" do
    # On insert we merge the fields and changes
    changeset = Ecto.Changeset.cast(%Post{visits: 13, title: "wrong"},
                                    %{"title" => "hello", "temp" => "unknown"}, ~w(title temp)a)

    post = TestRepo.insert!(changeset)
    assert %Post{visits: 13, title: "hello", temp: "unknown"} = post
    assert %Post{visits: 13, title: "hello", temp: "temp"} = TestRepo.get!(Post, post.id)

    # On update we merge only fields, direct schema changes are discarded
    changeset = Ecto.Changeset.cast(%{post | visits: 17},
                                    %{"title" => "world", "temp" => "unknown"}, ~w(title temp)a)

    assert %Post{visits: 17, title: "world", temp: "unknown"} = TestRepo.update!(changeset)
    assert %Post{visits: 13, title: "world", temp: "temp"} = TestRepo.get!(Post, post.id)
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

  @tag :no_primary_key
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
    changeset = Ecto.Changeset.cast(raw, %{"text" => "0"}, ~w(text)a)
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

      @primary_key {:id, CustomPermalink, autogenerate: true}
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
    changeset = Ecto.Changeset.cast(%Post{id: 11}, %{"id" => "13"}, ~w(id)a)
    assert %Post{id: 13} = post = TestRepo.insert!(changeset)

    changeset = Ecto.Changeset.cast(post, %{"id" => "15"}, ~w(id)a)
    assert %Post{id: 15} = TestRepo.update!(changeset)
  end

  test "insert and fetch a schema with utc timestamps" do
    datetime = DateTime.from_unix!(System.os_time(:second), :second)
    TestRepo.insert!(%User{inserted_at: datetime})
    assert [%{inserted_at: ^datetime}] = TestRepo.all(User)
  end

  test "optimistic locking in update/delete operations" do
    import Ecto.Changeset, only: [cast: 3, optimistic_lock: 2]
    base_post = TestRepo.insert!(%Comment{})

    changeset_ok =
      base_post
      |> cast(%{"text" => "foo.bar"}, ~w(text)a)
      |> optimistic_lock(:lock_version)
    TestRepo.update!(changeset_ok)

    changeset_stale = optimistic_lock(base_post, :lock_version)
    assert_raise Ecto.StaleEntryError, fn -> TestRepo.update!(changeset_stale) end
    assert_raise Ecto.StaleEntryError, fn -> TestRepo.delete!(changeset_stale) end
  end

  test "optimistic locking in update operation with nil field" do
    import Ecto.Changeset, only: [cast: 3, optimistic_lock: 3]

    base_post =
      %Comment{}
      |> cast(%{lock_version: nil}, [:lock_version])
      |> TestRepo.insert!()

    incrementer =
      fn
        nil -> 1
        old_value -> old_value + 1
      end

    changeset_ok =
      base_post
      |> cast(%{"text" => "foo.bar"}, ~w(text)a)
      |> optimistic_lock(:lock_version, incrementer)

    updated = TestRepo.update!(changeset_ok)
    assert updated.text == "foo.bar"
    assert updated.lock_version == 1
  end

  test "optimistic locking in delete operation with nil field" do
    import Ecto.Changeset, only: [cast: 3, optimistic_lock: 3]

    base_post =
      %Comment{}
      |> cast(%{lock_version: nil}, [:lock_version])
      |> TestRepo.insert!()

    incrementer =
      fn
        nil -> 1
        old_value -> old_value + 1
      end

    changeset_ok = optimistic_lock(base_post, :lock_version, incrementer)
    TestRepo.delete!(changeset_ok)

    refute TestRepo.get(Comment, base_post.id)
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

    assert exception.message =~ "posts_uuid_index (unique_constraint)"
    assert exception.message =~ "The changeset has not defined any constraint."
    assert exception.message =~ "call `unique_constraint/3`"

    message = ~r/constraint error when attempting to insert struct/
    exception =
      assert_raise Ecto.ConstraintError, message, fn ->
        changeset
        |> Ecto.Changeset.unique_constraint(:uuid, name: :posts_email_changeset)
        |> TestRepo.insert()
      end

    assert exception.message =~ "posts_email_changeset (unique_constraint)"

    {:error, changeset} =
      changeset
      |> Ecto.Changeset.unique_constraint(:uuid)
      |> TestRepo.insert()
    assert changeset.errors == [uuid: {"has already been taken", [constraint: :unique, constraint_name: "posts_uuid_index"]}]
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
        posts: [post.(uuid), post.(uuid), post.(Ecto.UUID.generate())]
      }

    [_, p2, _] = changeset.changes.posts
    assert p2.errors == [uuid: {"has already been taken", [constraint: :unique, constraint_name: "posts_uuid_index"]}]
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
    assert changeset.errors == [uuid: {"has already been taken", [constraint: :unique, constraint_name: "customs_uuid_index"]}]
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

    assert exception.message =~ "comments_post_id_fkey (foreign_key_constraint)"
    assert exception.message =~ "The changeset has not defined any constraint."
    assert exception.message =~ "call `foreign_key_constraint/3`"

    message = ~r/constraint error when attempting to insert struct/
    exception =
      assert_raise Ecto.ConstraintError, message, fn ->
        changeset
        |> Ecto.Changeset.foreign_key_constraint(:post_id, name: :comments_post_id_other)
        |> TestRepo.insert()
      end

    assert exception.message =~ "comments_post_id_other (foreign_key_constraint)"

    {:error, changeset} =
      changeset
      |> Ecto.Changeset.foreign_key_constraint(:post_id)
      |> TestRepo.insert()
    assert changeset.errors == [post_id: {"does not exist", [constraint: :foreign, constraint_name: "comments_post_id_fkey"]}]
  end

  @tag :foreign_key_constraint
  test "assoc constraint" do
    changeset = Ecto.Changeset.change(%Comment{post_id: 0})

    exception =
      assert_raise Ecto.ConstraintError, ~r/constraint error when attempting to insert struct/, fn ->
        changeset
        |> TestRepo.insert()
      end

    assert exception.message =~ "comments_post_id_fkey (foreign_key_constraint)"
    assert exception.message =~ "The changeset has not defined any constraint."

    message = ~r/constraint error when attempting to insert struct/
    exception =
      assert_raise Ecto.ConstraintError, message, fn ->
        changeset
        |> Ecto.Changeset.assoc_constraint(:post, name: :comments_post_id_other)
        |> TestRepo.insert()
      end

    assert exception.message =~ "comments_post_id_other (foreign_key_constraint)"

    {:error, changeset} =
      changeset
      |> Ecto.Changeset.assoc_constraint(:post)
      |> TestRepo.insert()
    assert changeset.errors == [post: {"does not exist", [constraint: :assoc, constraint_name: "comments_post_id_fkey"]}]
  end

  @tag :foreign_key_constraint
  test "no assoc constraint error" do
    user = TestRepo.insert!(%User{})
    TestRepo.insert!(%Permalink{user_id: user.id})

    exception =
      assert_raise Ecto.ConstraintError, ~r/constraint error when attempting to delete struct/, fn ->
        TestRepo.delete!(user)
      end

    assert exception.message =~ "permalinks_user_id_fkey (foreign_key_constraint)"
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

    assert exception.message =~ "permalinks_user_id_pther (foreign_key_constraint)"
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
    assert changeset.errors == [permalink: {"is still associated with this entry", [constraint: :no_assoc, constraint_name: "permalinks_user_id_fkey"]}]
  end

  @tag :foreign_key_constraint
  test "insert and update with embeds during failing child foreign key" do
    changeset =
      Order
      |> struct(%{})
      |> order_changeset(%{item: %{price: 10}, permalink: %{post_id: 0}})

    {:error, changeset} = TestRepo.insert(changeset)
    assert %Ecto.Changeset{} = changeset.changes.item

    order =
      Order
      |> struct(%{})
      |> order_changeset(%{})
      |> TestRepo.insert!()
      |> TestRepo.preload([:permalink])

    changeset = order_changeset(order, %{item: %{price: 10}, permalink: %{post_id: 0}})
    assert %Ecto.Changeset{} = changeset.changes.item

    {:error, changeset} = TestRepo.update(changeset)
    assert %Ecto.Changeset{} = changeset.changes.item
  end

  def order_changeset(order, params) do
    order
    |> Ecto.Changeset.cast(params, [:permalink_id])
    |> Ecto.Changeset.cast_embed(:item, with: &item_changeset/2)
    |> Ecto.Changeset.cast_assoc(:permalink, with: &permalink_changeset/2)
  end

  def item_changeset(item, params) do
    item
    |> Ecto.Changeset.cast(params, [:price])
  end

  def permalink_changeset(comment, params) do
    comment
    |> Ecto.Changeset.cast(params, [:post_id])
    |> Ecto.Changeset.assoc_constraint(:post)
  end

  test "unsafe_validate_unique/3" do
    {:ok, inserted_post} = TestRepo.insert(%Post{title: "Greetings", visits: 13})
    new_post_changeset = Post.changeset(%Post{}, %{title: "Greetings", visits: 17})

    changeset = Ecto.Changeset.unsafe_validate_unique(new_post_changeset, [:title], TestRepo)
    assert changeset.errors[:title] ==
           {"has already been taken", validation: :unsafe_unique, fields: [:title]}

    changeset = Ecto.Changeset.unsafe_validate_unique(new_post_changeset, [:title, :text], TestRepo)
    assert changeset.errors[:title] == nil

    update_changeset = Post.changeset(inserted_post, %{visits: 17})
    changeset = Ecto.Changeset.unsafe_validate_unique(update_changeset, [:title], TestRepo)
    assert changeset.errors[:title] == nil # cannot conflict with itself
  end

  test "unsafe_validate_unique/3 with composite keys" do
    {:ok, inserted_post} = TestRepo.insert(%CompositePk{a: 123, b: 456, name: "UniqueName"})

    different_pk = CompositePk.changeset(%CompositePk{}, %{name: "UniqueName", a: 789, b: 321})
    changeset = Ecto.Changeset.unsafe_validate_unique(different_pk, [:name], TestRepo)
    assert changeset.errors[:name] ==
      {"has already been taken", validation: :unsafe_unique, fields: [:name]}

    partial_pk = CompositePk.changeset(%CompositePk{}, %{name: "UniqueName", a: 789, b: 456})
    changeset = Ecto.Changeset.unsafe_validate_unique(partial_pk, [:name], TestRepo)
    assert changeset.errors[:name] ==
           {"has already been taken", validation: :unsafe_unique, fields: [:name]}

    update_changeset = CompositePk.changeset(inserted_post, %{name: "NewName"})
    changeset = Ecto.Changeset.unsafe_validate_unique(update_changeset, [:name], TestRepo)
    assert changeset.valid?
    assert changeset.errors[:name] == nil # cannot conflict with itself
  end

  test "get(!)" do
    post1 = TestRepo.insert!(%Post{title: "1"})
    post2 = TestRepo.insert!(%Post{title: "2"})

    assert post1 == TestRepo.get(Post, post1.id)
    assert post2 == TestRepo.get(Post, to_string post2.id) # With casting

    assert post1 == TestRepo.get!(Post, post1.id)
    assert post2 == TestRepo.get!(Post, to_string post2.id) # With casting

    TestRepo.delete!(post1)

    assert TestRepo.get(Post, post1.id) == nil
    assert_raise Ecto.NoResultsError, fn ->
      TestRepo.get!(Post, post1.id)
    end
  end

  test "get(!) with custom source" do
    custom = Ecto.put_meta(%Custom{}, source: "posts")
    custom = TestRepo.insert!(custom)
    bid    = custom.bid
    assert %Custom{bid: ^bid, __meta__: %{source: "posts"}} =
           TestRepo.get(from(c in {"posts", Custom}), bid)
  end

  test "get(!) with binary_id" do
    custom = TestRepo.insert!(%Custom{})
    bid = custom.bid
    assert %Custom{bid: ^bid} = TestRepo.get(Custom, bid)
  end

  test "get_by(!)" do
    post1 = TestRepo.insert!(%Post{title: "1", visits: 1})
    post2 = TestRepo.insert!(%Post{title: "2", visits: 2})

    assert post1 == TestRepo.get_by(Post, id: post1.id)
    assert post1 == TestRepo.get_by(Post, title: post1.title)
    assert post1 == TestRepo.get_by(Post, id: post1.id, title: post1.title)
    assert post2 == TestRepo.get_by(Post, id: to_string(post2.id)) # With casting
    assert nil   == TestRepo.get_by(Post, title: "hey")
    assert nil   == TestRepo.get_by(Post, id: post2.id, visits: 3)

    assert post1 == TestRepo.get_by!(Post, id: post1.id)
    assert post1 == TestRepo.get_by!(Post, title: post1.title)
    assert post1 == TestRepo.get_by!(Post, id: post1.id, visits: 1)
    assert post2 == TestRepo.get_by!(Post, id: to_string(post2.id)) # With casting

    assert post1 == TestRepo.get_by!(Post, %{id: post1.id})

    assert_raise Ecto.NoResultsError, fn ->
      TestRepo.get_by!(Post, id: post2.id, title: "hey")
    end
  end

  test "first, last and one(!)" do
    post1 = TestRepo.insert!(%Post{title: "1"})
    post2 = TestRepo.insert!(%Post{title: "2"})

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
    refute query |> last |> TestRepo.one
    assert_raise Ecto.NoResultsError, fn -> query |> first |> TestRepo.one! end
    assert_raise Ecto.NoResultsError, fn -> query |> last |> TestRepo.one! end
  end

  test "exists?" do
    TestRepo.insert!(%Post{title: "1", visits: 2})
    TestRepo.insert!(%Post{title: "2", visits: 1})

    query = from p in Post, where: not is_nil(p.title), limit: 2
    assert query |> TestRepo.exists? == true

    query = from p in Post, where: p.title == "1", select: p.title
    assert query |> TestRepo.exists? == true

    query = from p in Post, where: is_nil(p.id)
    assert query |> TestRepo.exists? == false

    query = from p in Post, where: is_nil(p.id)
    assert query |> TestRepo.exists? == false

    query = from(p in Post, select: {p.visits, avg(p.visits)}, group_by: p.visits, having: avg(p.visits) > 1)
    assert query |> TestRepo.exists? == true
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

    # With order_by
    query = from Post, order_by: [asc: :visits]
    assert TestRepo.aggregate(query, :max, :visits) == 14

    # With order_by and limit
    query = from Post, order_by: [asc: :visits], limit: 2
    assert TestRepo.aggregate(query, :max, :visits) == 12
  end

  @tag :decimal_precision
  test "aggregate avg" do
    TestRepo.insert!(%Post{visits: 10})
    TestRepo.insert!(%Post{visits: 12})
    TestRepo.insert!(%Post{visits: 14})
    TestRepo.insert!(%Post{visits: 14})

    assert "12.5" <> _ = to_string(TestRepo.aggregate(Post, :avg, :visits))
  end

  @tag :inline_order_by
  test "aggregate with distinct" do
    TestRepo.insert!(%Post{visits: 10})
    TestRepo.insert!(%Post{visits: 12})
    TestRepo.insert!(%Post{visits: 14})
    TestRepo.insert!(%Post{visits: 14})

    query = from Post, order_by: [asc: :visits], distinct: true
    assert TestRepo.aggregate(query, :count, :visits) == 3
  end

  @tag :insert_cell_wise_defaults
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

  @tag :insert_select
  test "insert all with query" do
    comment = TestRepo.insert!(%Comment{text: "1", lock_version: 1})

    text_query = from(c in Comment, select: c.text, where: [id: ^comment.id, lock_version: 1])

    lock_version_query = from(c in Comment, select: c.lock_version, where: [id: ^comment.id])

    rows = [
      [text: "2", lock_version: lock_version_query],
      [lock_version: lock_version_query, text: "3"],
      [text: text_query],
      [text: text_query, lock_version: lock_version_query],
      [lock_version: 6, text: "6"]
    ]
    assert {5, nil} = TestRepo.insert_all(Comment, rows, [])

    inserted_rows = Comment
                    |> where([c], c.id != ^comment.id)
                    |> TestRepo.all()

    assert [%Comment{text: "2", lock_version: 1},
            %Comment{text: "3", lock_version: 1},
            %Comment{text: "1"},
            %Comment{text: "1", lock_version: 1},
            %Comment{text: "6", lock_version: 6}] = inserted_rows
  end

  @tag :invalid_prefix
  @tag :insert_cell_wise_defaults
  test "insert all with invalid prefix" do
    assert catch_error(TestRepo.insert_all(Post, [[], []], prefix: "oops"))
  end

  @tag :returning
  @tag :insert_cell_wise_defaults
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
  @tag :insert_cell_wise_defaults
  test "insert all with returning with schema with field source" do
    assert {0, []} = TestRepo.insert_all(Permalink, [], returning: true)
    assert {0, nil} = TestRepo.insert_all(Permalink, [], returning: false)

    {2, [c1, c2]} = TestRepo.insert_all(Permalink, [[url: "1"], [url: "2"]], returning: [:id, :url])
    assert %Permalink{url: "1", __meta__: %{state: :loaded}} = c1
    assert %Permalink{url: "2", __meta__: %{state: :loaded}} = c2

    {2, [c1, c2]} = TestRepo.insert_all(Permalink, [[url: "3"], [url: "4"]], returning: true)
    assert %Permalink{url: "3", __meta__: %{state: :loaded}} = c1
    assert %Permalink{url: "4", __meta__: %{state: :loaded}} = c2
  end

  @tag :returning
  @tag :insert_cell_wise_defaults
  test "insert all with returning without schema" do
    {2, [c1, c2]} = TestRepo.insert_all("comments", [[text: "1"], [text: "2"]], returning: [:id, :text])
    assert %{id: _, text: "1"} = c1
    assert %{id: _, text: "2"} = c2

    assert_raise ArgumentError, fn ->
      TestRepo.insert_all("comments", [[text: "1"], [text: "2"]], returning: true)
    end
  end

  @tag :insert_cell_wise_defaults
  test "insert all with dumping" do
    uuid = Ecto.UUID.generate()
    assert {1, nil} = TestRepo.insert_all(Post, [%{uuid: uuid}])
    assert [%Post{uuid: ^uuid, title: nil}] = TestRepo.all(Post)
  end

  @tag :insert_cell_wise_defaults
  test "insert all autogenerates for binary_id type" do
    custom = TestRepo.insert!(%Custom{bid: nil})
    assert custom.bid
    assert TestRepo.get(Custom, custom.bid)
    assert TestRepo.delete!(custom)
    refute TestRepo.get(Custom, custom.bid)

    uuid = Ecto.UUID.generate()
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

    assert {3, nil} = TestRepo.update_all("posts", [set: [title: nil]])

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

    assert {3, posts} = TestRepo.update_all(select(Post, [p], p), [set: [title: "x"]])

    [p1, p2, p3] = Enum.sort_by(posts, & &1.id)
    assert %Post{id: ^id1, title: "x"} = p1
    assert %Post{id: ^id2, title: "x"} = p2
    assert %Post{id: ^id3, title: "x"} = p3

    assert {3, posts} = TestRepo.update_all(select(Post, [:id, :visits]), [set: [visits: 11]])

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

    assert {3, posts} = TestRepo.update_all(select("posts", [:id, :title]), [set: [title: "x"]])

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
                            update: [set: [visits: ^17]])
    assert {2, nil} = TestRepo.update_all(query, set: [title: "x"])

    assert %Post{title: "x", visits: 17} = TestRepo.get(Post, id1)
    assert %Post{title: "x", visits: 17} = TestRepo.get(Post, id2)
    assert %Post{title: "3", visits: nil} = TestRepo.get(Post, id3)
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
    visits = 13
    datetime = ~N[2014-01-16 20:26:51]
    assert %Post{id: id} = TestRepo.insert!(%Post{})

    assert {1, nil} = TestRepo.update_all(Post, set: [visits: visits, inserted_at: datetime])
    assert %Post{visits: 13, inserted_at: ^datetime} = TestRepo.get(Post, id)
  end

  test "delete all" do
    assert %Post{} = TestRepo.insert!(%Post{title: "1"})
    assert %Post{} = TestRepo.insert!(%Post{title: "2"})
    assert %Post{} = TestRepo.insert!(%Post{title: "3"})

    assert {3, nil} = TestRepo.delete_all(Post)
    assert [] = TestRepo.all(Post)
  end

  @tag :invalid_prefix
  test "delete all with invalid prefix" do
    assert catch_error(TestRepo.delete_all(Post, prefix: "oops"))
  end

  @tag :returning
  test "delete all with returning with schema" do
    assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1"})
    assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2"})
    assert %Post{id: id3} = TestRepo.insert!(%Post{title: "3"})

    assert {3, posts} = TestRepo.delete_all(select(Post, [p], p))

    [p1, p2, p3] = Enum.sort_by(posts, & &1.id)
    assert %Post{id: ^id1, title: "1"} = p1
    assert %Post{id: ^id2, title: "2"} = p2
    assert %Post{id: ^id3, title: "3"} = p3
  end

  @tag :returning
  test "delete all with returning without schema" do
    assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1"})
    assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2"})
    assert %Post{id: id3} = TestRepo.insert!(%Post{title: "3"})

    assert {3, posts} = TestRepo.delete_all(select("posts", [:id, :title]))

    [p1, p2, p3] = Enum.sort_by(posts, & &1.id)
    assert p1 == %{id: id1, title: "1"}
    assert p2 == %{id: id2, title: "2"}
    assert p3 == %{id: id3, title: "3"}
  end

  test "delete all with filter" do
    assert %Post{} = TestRepo.insert!(%Post{title: "1"})
    assert %Post{} = TestRepo.insert!(%Post{title: "2"})
    assert %Post{} = TestRepo.insert!(%Post{title: "3"})

    query = from(p in Post, where: p.title == "1" or p.title == "2")
    assert {2, nil} = TestRepo.delete_all(query)
    assert [%Post{}] = TestRepo.all(Post)
  end

  test "delete all no entries" do
    assert %Post{id: id1} = TestRepo.insert!(%Post{title: "1"})
    assert %Post{id: id2} = TestRepo.insert!(%Post{title: "2"})
    assert %Post{id: id3} = TestRepo.insert!(%Post{title: "3"})

    query = from(p in Post, where: p.title == "4")
    assert {0, nil} = TestRepo.delete_all(query)
    assert %Post{title: "1"} = TestRepo.get(Post, id1)
    assert %Post{title: "2"} = TestRepo.get(Post, id2)
    assert %Post{title: "3"} = TestRepo.get(Post, id3)
  end

  test "virtual field" do
    assert %Post{id: id} = TestRepo.insert!(%Post{title: "1"})
    assert TestRepo.get(Post, id).temp == "temp"
  end

  ## Query syntax

  defmodule Foo do
    defstruct [:title]
  end

  describe "query select" do
    test "expressions" do
      %Post{} = TestRepo.insert!(%Post{title: "1", visits: 13})

      assert [{"1", 13}] ==
             TestRepo.all(from p in Post, select: {p.title, p.visits})

      assert [["1", 13]] ==
             TestRepo.all(from p in Post, select: [p.title, p.visits])

      assert [%{:title => "1", 3 => 13, "visits" => 13}] ==
             TestRepo.all(from p in Post, select: %{
               :title => p.title,
               "visits" => p.visits,
               3 => p.visits
             })

      assert [%{:title => "1", "1" => 13, "visits" => 13}] ==
             TestRepo.all(from p in Post, select: %{
               :title  => p.title,
               p.title => p.visits,
               "visits"  => p.visits
             })

      assert [%Foo{title: "1"}] ==
             TestRepo.all(from p in Post, select: %Foo{title: p.title})
    end

    test "map update" do
      %Post{} = TestRepo.insert!(%Post{title: "1", visits: 13})

      assert [%Post{:title => "new title", visits: 13}] =
             TestRepo.all(from p in Post, select: %{p | title: "new title"})

      assert [%Post{title: "new title", visits: 13}] =
        TestRepo.all(from p in Post, select: %Post{p | title: "new title"})

      assert_raise KeyError, fn ->
        TestRepo.all(from p in Post, select: %{p | unknown: "new title"})
      end

      assert_raise BadMapError, fn ->
        TestRepo.all(from p in Post, select: %{p.title | title: "new title"})
      end

      assert_raise BadStructError, fn ->
        TestRepo.all(from p in Post, select: %Foo{p | title: p.title})
      end
    end

    test "take with structs" do
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

    test "take with maps" do
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

    test "take with preload assocs" do
      %{id: pid} = TestRepo.insert!(%Post{title: "post"})
      TestRepo.insert!(%Comment{post_id: pid, text: "comment"})
      fields = [:id, :title, comments: [:text, :post_id]]

      [p] = Post |> preload(:comments) |> select([p], ^fields) |> TestRepo.all
      assert %Post{title: "post"} = p
      assert [%Comment{text: "comment"}] = p.comments

      [p] = Post |> preload(:comments) |> select([p], struct(p, ^fields)) |> TestRepo.all
      assert %Post{title: "post"} = p
      assert [%Comment{text: "comment"}] = p.comments

      [p] = Post |> preload(:comments) |> select([p], map(p, ^fields)) |> TestRepo.all
      assert p == %{id: pid, title: "post", comments: [%{text: "comment", post_id: pid}]}
    end

    test "take with nil preload assoc" do
      %{id: cid} = TestRepo.insert!(%Comment{text: "comment"})
      fields = [:id, :text, post: [:title]]

      [c] = Comment |> preload(:post) |> select([c], ^fields) |> TestRepo.all
      assert %Comment{id: ^cid, text: "comment", post: nil} = c

      [c] = Comment |> preload(:post) |> select([c], struct(c, ^fields)) |> TestRepo.all
      assert %Comment{id: ^cid, text: "comment", post: nil} = c

      [c] = Comment |> preload(:post) |> select([c], map(c, ^fields)) |> TestRepo.all
      assert c == %{id: cid, text: "comment", post: nil}
    end

    test "take with join assocs" do
      %{id: pid} = TestRepo.insert!(%Post{title: "post"})
      %{id: cid} = TestRepo.insert!(%Comment{post_id: pid, text: "comment"})
      fields = [:id, :title, comments: [:text, :post_id, :id]]
      query = from p in Post, where: p.id == ^pid, join: c in assoc(p, :comments), preload: [comments: c]

      p = TestRepo.one(from q in query, select: ^fields)
      assert %Post{title: "post"} = p
      assert [%Comment{text: "comment"}] = p.comments

      p = TestRepo.one(from q in query, select: struct(q, ^fields))
      assert %Post{title: "post"} = p
      assert [%Comment{text: "comment"}] = p.comments

      p = TestRepo.one(from q in query, select: map(q, ^fields))
      assert p == %{id: pid, title: "post", comments: [%{text: "comment", post_id: pid, id: cid}]}
    end

    test "take with single nil column" do
      %Post{} = TestRepo.insert!(%Post{title: "1", counter: nil})
      assert %{counter: nil} =
             TestRepo.one(from p in Post, where: p.title == "1", select: [:counter])
    end

    test "take with join assocs and single nil column" do
      %{id: post_id} = TestRepo.insert!(%Post{title: "1"}, counter: nil)
      TestRepo.insert!(%Comment{post_id: post_id, text: "comment"})
      assert %{counter: nil} ==
              TestRepo.one(from p in Post, join: c in assoc(p, :comments), where: p.title == "1", select:  map(p, [:counter]))
    end

    test "field source" do
      TestRepo.insert!(%Permalink{url: "url"})
      assert ["url"] = Permalink |> select([p], p.url) |> TestRepo.all()
      assert [1] = Permalink |> select([p], count(p.url)) |> TestRepo.all()
    end

    test "merge" do
      date = Date.utc_today()
      %Post{id: post_id} = TestRepo.insert!(%Post{title: "1", counter: nil, posted: date, public: false})

      # Merge on source
      assert [%Post{title: "2"}] =
             Post |> select([p], merge(p, %{title: "2"})) |> TestRepo.all()
      assert [%Post{title: "2"}] =
             Post |> select([p], p) |> select_merge([p], %{title: "2"}) |> TestRepo.all()

      # Merge on struct
      assert [%Post{title: "2"}] =
             Post |> select([p], merge(%Post{title: p.title}, %{title: "2"})) |> TestRepo.all()
      assert [%Post{title: "2"}] =
             Post |> select([p], %Post{title: p.title}) |> select_merge([p], %{title: "2"}) |> TestRepo.all()

      # Merge on map
      assert [%{title: "2"}] =
             Post |> select([p], merge(%{title: p.title}, %{title: "2"})) |> TestRepo.all()
      assert [%{title: "2"}] =
             Post |> select([p], %{title: p.title}) |> select_merge([p], %{title: "2"}) |> TestRepo.all()

      # Merge on outer join with map
      %Permalink{} = TestRepo.insert!(%Permalink{post_id: post_id, url: "Q", title: "Z"})

      # left join record is present
      assert [%{url: "Q", title: "1", posted: _date}] =
               Permalink
               |> join(:left, [l], p in Post, on: l.post_id == p.id)
               |> select([l, p], merge(l, map(p, ^~w(title posted)a)))
               |> TestRepo.all()

      assert [%{url: "Q", title: "1", posted: _date}] =
               Permalink
               |> join(:left, [l], p in Post, on: l.post_id == p.id)
               |> select_merge([_l, p], map(p, ^~w(title posted)a))
               |> TestRepo.all()

      # left join record is not present
      assert [%{url: "Q", title: "Z", posted: nil}] =
               Permalink
               |> join(:left, [l], p in Post, on: l.post_id == p.id and p.public == true)
               |> select([l, p], merge(l, map(p, ^~w(title posted)a)))
               |> TestRepo.all()

      assert [%{url: "Q", title: "Z", posted: nil}] =
               Permalink
               |> join(:left, [l], p in Post, on: l.post_id == p.id and p.public == true)
               |> select_merge([_l, p], map(p, ^~w(title posted)a))
               |> TestRepo.all()
    end

    test "merge with update on self" do
      %Post{} = TestRepo.insert!(%Post{title: "1", counter: 1})

      assert [%Post{title: "1", counter: 2}] =
        Post |> select([p], merge(p, %{p | counter: 2})) |> TestRepo.all()
      assert [%Post{title: "1", counter: 2}] =
        Post |> select([p], p) |> select_merge([p], %{p | counter: 2}) |> TestRepo.all()
    end

    test "merge within subquery" do
      %Post{} = TestRepo.insert!(%Post{title: "1", counter: 1})

      subquery =
        Post
        |> select_merge([p], %{p | counter: 2})
        |> subquery()

      assert [%Post{title: "1", counter: 2}] = TestRepo.all(subquery)
    end
  end

  test "query count distinct" do
    TestRepo.insert!(%Post{title: "1"})
    TestRepo.insert!(%Post{title: "1"})
    TestRepo.insert!(%Post{title: "2"})

    assert [3] == Post |> select([p], count(p.title)) |> TestRepo.all
    assert [2] == Post |> select([p], count(p.title, :distinct)) |> TestRepo.all
  end

  test "query where interpolation" do
    post1 = TestRepo.insert!(%Post{title: "hello"})
    post2 = TestRepo.insert!(%Post{title: "goodbye"})

    assert [post1, post2] == Post |> where([], []) |> TestRepo.all |> Enum.sort_by(& &1.id)
    assert [post1]        == Post |> where([], [title: "hello"]) |> TestRepo.all
    assert [post1]        == Post |> where([], [title: "hello", id: ^post1.id]) |> TestRepo.all

    params0 = []
    params1 = [title: "hello"]
    params2 = [title: "hello", id: post1.id]
    assert [post1, post2]  == (from Post, where: ^params0) |> TestRepo.all |> Enum.sort_by(& &1.id)
    assert [post1]         == (from Post, where: ^params1) |> TestRepo.all
    assert [post1]         == (from Post, where: ^params2) |> TestRepo.all

    post3 = TestRepo.insert!(%Post{title: "goodbye", uuid: nil})
    params3 = [title: "goodbye", uuid: post3.uuid]
    assert [post3] == (from Post, where: ^params3) |> TestRepo.all
  end

  describe "upsert via insert" do
    @describetag :upsert

    test "on conflict raise" do
      {:ok, inserted} = TestRepo.insert(%Post{title: "first"}, on_conflict: :raise)
      assert catch_error(TestRepo.insert(%Post{id: inserted.id, title: "second"}, on_conflict: :raise))
    end

    test "on conflict ignore" do
      post = %Post{title: "first", uuid: Ecto.UUID.generate()}
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
      post = %Post{uuid: Ecto.UUID.generate(),
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
      post = %Post{title: "first", uuid: Ecto.UUID.generate()}
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
      post = %Post{title: "first", uuid: Ecto.UUID.generate()}
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
      post = %Post{title: "first", uuid: Ecto.UUID.generate()}
      {:ok, inserted} = TestRepo.insert(post, on_conflict: on_conflict, conflict_target: [:uuid])
      assert inserted.id

      # Error on non-conflict target
      assert catch_error(TestRepo.insert(post, on_conflict: on_conflict, conflict_target: [:id]))

      {:ok, updated} = TestRepo.insert(post, on_conflict: on_conflict, conflict_target: [:uuid])
      assert updated.id == inserted.id
      assert updated.title != "second"
      assert TestRepo.get!(Post, inserted.id).title == "second"
    end

    @tag :returning
    @tag :with_conflict_target
    test "on conflict keyword list and conflict target and returning" do
      {:ok, c1} = TestRepo.insert(%Post{})
      {:ok, c2} = TestRepo.insert(%Post{id: c1.id}, on_conflict: [set: [id: c1.id]], conflict_target: [:id], returning: [:id, :uuid])
      {:ok, c3} = TestRepo.insert(%Post{id: c1.id}, on_conflict: [set: [id: c1.id]], conflict_target: [:id], returning: true)
      {:ok, c4} = TestRepo.insert(%Post{id: c1.id}, on_conflict: [set: [id: c1.id]], conflict_target: [:id], returning: false)

      assert c2.uuid == c1.uuid
      assert c3.uuid == c1.uuid
      assert c4.uuid != c1.uuid
    end

    @tag :returning
    @tag :with_conflict_target
    test "on conflict keyword list and conflict target and returning and field source" do
      TestRepo.insert!(%Permalink{url: "old"})
      {:ok, c1} = TestRepo.insert(%Permalink{url: "old"},
                                  on_conflict: [set: [url: "new1"]],
                                  conflict_target: [:url],
                                  returning: [:url])

      TestRepo.insert!(%Permalink{url: "old"})
      {:ok, c2} = TestRepo.insert(%Permalink{url: "old"},
                                  on_conflict: [set: [url: "new2"]],
                                  conflict_target: [:url],
                                  returning: true)

      assert c1.url == "new1"
      assert c2.url == "new2"
    end

    @tag :returning
    @tag :with_conflict_target
    test "on conflict ignore and returning" do
      post = %Post{title: "first", uuid: Ecto.UUID.generate()}
      {:ok, inserted} = TestRepo.insert(post, on_conflict: :nothing, conflict_target: [:uuid])
      assert inserted.id

      {:ok, not_inserted} = TestRepo.insert(post, on_conflict: :nothing, conflict_target: [:uuid], returning: true)
      assert not_inserted.id == nil
    end

    @tag :without_conflict_target
    test "on conflict query" do
      on_conflict = from Post, update: [set: [title: "second"]]
      post = %Post{title: "first", uuid: Ecto.UUID.generate()}
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
      post = %Post{title: "first", uuid: Ecto.UUID.generate()}
      {:ok, inserted} = TestRepo.insert(post, on_conflict: on_conflict, conflict_target: [:uuid])
      assert inserted.id

      # Error on non-conflict target
      assert catch_error(TestRepo.insert(post, on_conflict: on_conflict, conflict_target: [:id]))

      {:ok, updated} = TestRepo.insert(post, on_conflict: on_conflict, conflict_target: [:uuid])
      assert updated.id == inserted.id
      assert updated.title != "second"
      assert TestRepo.get!(Post, inserted.id).title == "second"
    end

    @tag :with_conflict_target
    test "on conflict query having condition" do
      post = %Post{title: "first", counter: 1, uuid: Ecto.UUID.generate()}
      {:ok, inserted} = TestRepo.insert(post)

      on_conflict = from Post, where: [counter: 2], update: [set: [title: "second"]]

      insert_options = [
        on_conflict: on_conflict,
        conflict_target: [:uuid],
        stale_error_field: :counter
      ]

      assert {:error, changeset} = TestRepo.insert(post, insert_options)
      assert changeset.errors == [counter: {"is stale", [stale: true]}]

      assert TestRepo.get!(Post, inserted.id).title == "first"
    end

    @tag :without_conflict_target
    test "on conflict replace_all" do
      post = %Post{title: "first", visits: 13, uuid: Ecto.UUID.generate()}
      {:ok, inserted} = TestRepo.insert(post, on_conflict: :replace_all)
      assert inserted.id

      post = %Post{title: "updated", visits: 17, uuid: post.uuid}
      post = TestRepo.insert!(post, on_conflict: :replace_all)
      assert post.id != inserted.id
      assert post.title == "updated"
      assert post.visits == 17

      assert TestRepo.all(from p in Post, select: {p.id, p.title, p.visits}) ==
             [{post.id, "updated", 17}]
      assert TestRepo.all(from p in Post, select: count(p.id)) == [1]
    end

    @tag :with_conflict_target
    test "on conflict replace_all and conflict target" do
      post = %Post{title: "first", visits: 13, uuid: Ecto.UUID.generate()}
      {:ok, inserted} = TestRepo.insert(post, on_conflict: :replace_all, conflict_target: :uuid)
      assert inserted.id

      post = %Post{title: "updated", visits: 17, uuid: post.uuid}
      post = TestRepo.insert!(post, on_conflict: :replace_all, conflict_target: :uuid)
      assert post.id != inserted.id
      assert post.title == "updated"
      assert post.visits == 17

      assert TestRepo.all(from p in Post, select: {p.id, p.title, p.visits}) ==
             [{post.id, "updated", 17}]
      assert TestRepo.all(from p in Post, select: count(p.id)) == [1]
    end
  end

  describe "upsert via insert_all" do
    @describetag :upsert_all

    test "on conflict raise" do
      post = [title: "first", uuid: Ecto.UUID.generate()]
      {1, nil} = TestRepo.insert_all(Post, [post], on_conflict: :raise)
      assert catch_error(TestRepo.insert_all(Post, [post], on_conflict: :raise))
    end

    test "on conflict ignore" do
      post = [title: "first", uuid: Ecto.UUID.generate()]
      assert TestRepo.insert_all(Post, [post], on_conflict: :nothing) == {1, nil}

      # PG returns 0, MySQL returns 1
      {entries, nil} = TestRepo.insert_all(Post, [post], on_conflict: :nothing)
      assert entries == 0 or entries == 1

      assert length(TestRepo.all(Post)) == 1
    end

    @tag :with_conflict_target
    test "on conflict ignore and conflict target" do
      post = [title: "first", uuid: Ecto.UUID.generate()]
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
      post = [title: "first", uuid: Ecto.UUID.generate()]
      {1, nil} = TestRepo.insert_all(Post, [post], on_conflict: on_conflict, conflict_target: [:uuid])

      # Error on non-conflict target
      assert catch_error(TestRepo.insert_all(Post, [post], on_conflict: on_conflict, conflict_target: [:id]))

      # Error on conflict target
      assert TestRepo.insert_all(Post, [post], on_conflict: on_conflict, conflict_target: [:uuid]) ==
             {1, nil}
      assert TestRepo.all(from p in Post, select: p.title) == ["second"]
    end

    @tag :with_conflict_target
    @tag :returning
    test "on conflict keyword list and conflict target and returning and source field" do
      on_conflict = [set: [url: "new"]]
      permalink = [url: "old"]

      assert {1, [%Permalink{url: "old"}]} =
             TestRepo.insert_all(Permalink, [permalink],
                                 on_conflict: on_conflict, conflict_target: [:url], returning: [:url])

      assert {1, [%Permalink{url: "new"}]} =
             TestRepo.insert_all(Permalink, [permalink],
                                 on_conflict: on_conflict, conflict_target: [:url], returning: [:url])
    end

    @tag :with_conflict_target
    test "on conflict query and conflict target" do
      on_conflict = from Post, update: [set: [title: "second"]]
      post = [title: "first", uuid: Ecto.UUID.generate()]
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
      post = [title: "first", uuid: Ecto.UUID.generate()]
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
      {:ok, uuid} = Ecto.UUID.dump(Ecto.UUID.generate())
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
      post_first = %Post{title: "first", public: true, uuid: Ecto.UUID.generate()}
      post_second = %Post{title: "second", public: false, uuid: Ecto.UUID.generate()}

      {:ok, post_first} = TestRepo.insert(post_first, on_conflict: :replace_all)
      {:ok, post_second} = TestRepo.insert(post_second, on_conflict: :replace_all)

      assert post_first.id
      assert post_second.id
      assert TestRepo.all(from p in Post, select: count(p.id)) == [2]

      # Multiple record change value: note IDS are also replaced
      changes = [%{id: post_first.id + 2, title: "first_updated",
                   visits: 1, uuid: post_first.uuid},
                 %{id: post_second.id + 2, title: "second_updated",
                   visits: 2, uuid: post_second.uuid}]

      TestRepo.insert_all(Post, changes, on_conflict: :replace_all)
      assert TestRepo.all(from p in Post, select: count(p.id)) == [2]

      updated_first = TestRepo.get(Post, post_first.id + 2)
      assert updated_first.title == "first_updated"
      assert updated_first.visits == 1

      updated_second = TestRepo.get(Post, post_second.id + 2)
      assert updated_second.title == "second_updated"
      assert updated_second.visits == 2
    end

    @tag :with_conflict_target
    test "on conflict replace_all and conflict_target" do
      post_first = %Post{title: "first", public: true, uuid: Ecto.UUID.generate()}
      post_second = %Post{title: "second", public: false, uuid: Ecto.UUID.generate()}

      {:ok, post_first} = TestRepo.insert(post_first, on_conflict: :replace_all, conflict_target: :uuid)
      {:ok, post_second} = TestRepo.insert(post_second, on_conflict: :replace_all, conflict_target: :uuid)

      assert post_first.id
      assert post_second.id
      assert TestRepo.all(from p in Post, select: count(p.id)) == [2]

      # Multiple record change value: note IDS are also replaced
      changes = [%{id: post_second.id + 1, title: "first_updated",
                   visits: 1, uuid: post_first.uuid},
                 %{id: post_second.id + 2, title: "second_updated",
                   visits: 2, uuid: post_second.uuid}]

      TestRepo.insert_all(Post, changes, on_conflict: :replace_all, conflict_target: :uuid)
      assert TestRepo.all(from p in Post, select: count(p.id)) == [2]

      updated_first = TestRepo.get(Post, post_second.id + 1)
      assert updated_first.title == "first_updated"
      assert updated_first.visits == 1

      updated_second = TestRepo.get(Post, post_second.id + 2)
      assert updated_second.title == "second_updated"
      assert updated_second.visits == 2
    end

    @tag :without_conflict_target
    test "on conflict replace_all_except" do
      post_first = %Post{title: "first", public: true, uuid: Ecto.UUID.generate()}
      post_second = %Post{title: "second", public: false, uuid: Ecto.UUID.generate()}

      {:ok, post_first} = TestRepo.insert(post_first, on_conflict: {:replace_all_except, [:id]})
      {:ok, post_second} = TestRepo.insert(post_second, on_conflict: {:replace_all_except, [:id]})

      assert post_first.id
      assert post_second.id
      assert TestRepo.all(from p in Post, select: count(p.id)) == [2]

      # Multiple record change value: note IDS are not replaced
      changes = [%{id: post_first.id + 2, title: "first_updated",
                   visits: 1, uuid: post_first.uuid},
                 %{id: post_second.id + 2, title: "second_updated",
                   visits: 2, uuid: post_second.uuid}]

      TestRepo.insert_all(Post, changes, on_conflict: {:replace_all_except, [:id]})
      assert TestRepo.all(from p in Post, select: count(p.id)) == [2]

      updated_first = TestRepo.get(Post, post_first.id)
      assert updated_first.title == "first_updated"
      assert updated_first.visits == 1

      updated_second = TestRepo.get(Post, post_second.id)
      assert updated_second.title == "second_updated"
      assert updated_second.visits == 2
    end

    @tag :with_conflict_target
    test "on conflict replace_all_except and conflict_target" do
      post_first = %Post{title: "first", public: true, uuid: Ecto.UUID.generate()}
      post_second = %Post{title: "second", public: false, uuid: Ecto.UUID.generate()}

      {:ok, post_first} = TestRepo.insert(post_first, on_conflict: {:replace_all_except, [:id]}, conflict_target: :uuid)
      {:ok, post_second} = TestRepo.insert(post_second, on_conflict: {:replace_all_except, [:id]}, conflict_target: :uuid)

      assert post_first.id
      assert post_second.id
      assert TestRepo.all(from p in Post, select: count(p.id)) == [2]

      # Multiple record change value: note IDS are not replaced
      changes = [%{id: post_first.id + 2, title: "first_updated",
                   visits: 1, uuid: post_first.uuid},
                 %{id: post_second.id + 2, title: "second_updated",
                   visits: 2, uuid: post_second.uuid}]

      TestRepo.insert_all(Post, changes, on_conflict: {:replace_all_except, [:id]}, conflict_target: :uuid)
      assert TestRepo.all(from p in Post, select: count(p.id)) == [2]

      updated_first = TestRepo.get(Post, post_first.id)
      assert updated_first.title == "first_updated"
      assert updated_first.visits == 1

      updated_second = TestRepo.get(Post, post_second.id)
      assert updated_second.title == "second_updated"
      assert updated_second.visits == 2
    end

    @tag :with_conflict_target
    test "on conflict replace and conflict_target" do
      post_first = %Post{title: "first", visits: 10, public: true, uuid: Ecto.UUID.generate()}
      post_second = %Post{title: "second", visits: 20, public: false, uuid: Ecto.UUID.generate()}

      {:ok, post_first} = TestRepo.insert(post_first, on_conflict: {:replace, [:title, :visits]}, conflict_target: :uuid)
      {:ok, post_second} = TestRepo.insert(post_second, on_conflict: {:replace, [:title, :visits]}, conflict_target: :uuid)

      assert post_first.id
      assert post_second.id
      assert TestRepo.all(from p in Post, select: count(p.id)) == [2]

      # Multiple record change value: note `public` field is not changed
      changes = [%{id: post_first.id, title: "first_updated", visits: 11, public: false, uuid: post_first.uuid},
                 %{id: post_second.id, title: "second_updated", visits: 21, public: true, uuid: post_second.uuid}]

      TestRepo.insert_all(Post, changes, on_conflict: {:replace, [:title, :visits]}, conflict_target: :uuid)
      assert TestRepo.all(from p in Post, select: count(p.id)) == [2]

      updated_first = TestRepo.get(Post, post_first.id)
      assert updated_first.title == "first_updated"
      assert updated_first.visits == 11
      assert updated_first.public == true

      updated_second = TestRepo.get(Post, post_second.id)
      assert updated_second.title == "second_updated"
      assert updated_second.visits == 21
      assert updated_second.public == false
    end
  end
end
