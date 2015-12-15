defmodule Ecto.AssociationTest do
  use ExUnit.Case, async: true
  doctest Ecto.Association

  import Ecto
  import Ecto.Query, only: [from: 2]

  alias Ecto.Changeset
  alias Ecto.Changeset.Relation

  alias __MODULE__.Author
  alias __MODULE__.Comment
  alias __MODULE__.Permalink
  alias __MODULE__.Post
  alias __MODULE__.Summary
  alias __MODULE__.Email
  alias __MODULE__.Profile

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field :title, :string

      has_many :comments, Comment
      has_one :permalink, Permalink
      has_many :permalinks, Permalink
      belongs_to :author, Author
      belongs_to :summary, Summary
    end

    def changeset(model, params) do
      Changeset.cast(model, params, ~w(title), ~w(author_id))
    end

    def set_action(model, params) do
      Changeset.cast(model, params, ~w(title))
      |> Map.put(:action, :update)
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field :text, :string

      belongs_to :post, Post
      has_one :permalink, Permalink
      has_one :post_author, through: [:post, :author]       # belongs -> belongs
      has_one :post_permalink, through: [:post, :permalink] # belongs -> one
    end
  end

  defmodule Permalink do
    use Ecto.Schema

    schema "permalinks" do
      field :url, :string
    end

    def changeset(model, params) do
      import Ecto.Changeset
      model
      |> cast(params, ~w(url), ~w())
      |> validate_length(:url, min: 3)
    end
  end

  defmodule Author do
    use Ecto.Schema

    schema "authors" do
      field :title, :string
      has_many :posts, Post, on_replace: :delete
      has_many :posts_comments, through: [:posts, :comments]    # many -> many
      has_many :posts_permalinks, through: [:posts, :permalink] # many -> one
      has_many :emails, {"users_emails", Email}
      has_one :profile, {"users_profiles", Profile},
        defaults: [name: "default"], on_replace: :delete
    end
  end

  defmodule Summary do
    use Ecto.Schema

    schema "summaries" do
      has_one :post, Post, defaults: [title: "default"], on_replace: :nilify
      has_many :posts, Post, on_replace: :nilify
      has_one :post_author, through: [:post, :author]        # one -> belongs
      has_many :post_comments, through: [:post, :comments]   # one -> many
    end
  end

  defmodule Email do
    use Ecto.Schema

    schema "emails" do
      belongs_to :author, {"post_authors", Author}
    end
  end

  defmodule Profile do
    use Ecto.Schema

    schema "profiles" do
      field :name
      belongs_to :author, Author
      belongs_to :summary, Summary
    end

    def changeset(model, params) do
      Changeset.cast(model, params, ~w(name), ~w(id))
    end

    def optional_changeset(model, params) do
      Changeset.cast(model, params, ~w(), ~w(name))
    end

    def set_action(model, params) do
      Changeset.cast(model, params, ~w(name), ~w(id))
      |> Map.put(:action, :update)
    end
  end

  defp cast(model, params, assoc, opts \\ []) do
    model
    |> Changeset.cast(params, ~w(), ~w())
    |> Changeset.cast_assoc(assoc, opts)
  end

  ## Unit tests

  test "has many" do
    assoc = Post.__schema__(:association, :comments)

    assert inspect(Ecto.Association.Has.joins_query(assoc)) ==
           inspect(from p in Post, join: c in Comment, on: c.post_id == p.id)

    assert inspect(Ecto.Association.Has.assoc_query(assoc, [])) ==
           inspect(from c in Comment, where: c.post_id in ^[])

    assert inspect(Ecto.Association.Has.assoc_query(assoc, [1, 2, 3])) ==
           inspect(from c in Comment, where: c.post_id in ^[1, 2, 3])
  end

  test "has many model with specified source" do
    assoc = Author.__schema__(:association, :emails)

    assert inspect(Ecto.Association.Has.joins_query(assoc)) ==
           inspect(from a in Author, join: e in {"users_emails", Email}, on: e.author_id == a.id)

    assert inspect(Ecto.Association.Has.assoc_query(assoc, [])) ==
           inspect(from e in {"users_emails", Email}, where: e.author_id in ^[])

    assert inspect(Ecto.Association.Has.assoc_query(assoc, [1, 2, 3])) ==
           inspect(from e in {"users_emails", Email}, where: e.author_id in ^[1, 2, 3])
  end

  test "has many custom assoc query" do
    assoc = Post.__schema__(:association, :comments)
    query = from c in Comment, limit: 5
    assert inspect(Ecto.Association.Has.assoc_query(assoc, query, [1, 2, 3])) ==
           inspect(from c in Comment, where: c.post_id in ^[1, 2, 3], limit: 5)
  end

  test "has one" do
    assoc = Post.__schema__(:association, :permalink)

    assert inspect(Ecto.Association.Has.joins_query(assoc)) ==
           inspect(from p in Post, join: c in Permalink, on: c.post_id == p.id)

    assert inspect(Ecto.Association.Has.assoc_query(assoc, [])) ==
           inspect(from c in Permalink, where: c.post_id in ^[])

    assert inspect(Ecto.Association.Has.assoc_query(assoc, [1, 2, 3])) ==
           inspect(from c in Permalink, where: c.post_id in ^[1, 2, 3])
  end

  test "has one model with specified source" do
    assoc = Author.__schema__(:association, :profile)

    assert inspect(Ecto.Association.Has.joins_query(assoc)) ==
           inspect(from a in Author, join: p in {"users_profiles", Profile}, on: p.author_id == a.id)

    assert inspect(Ecto.Association.Has.assoc_query(assoc, [])) ==
           inspect(from p in {"users_profiles", Profile}, where: p.author_id in ^[])

    assert inspect(Ecto.Association.Has.assoc_query(assoc, [1, 2, 3])) ==
           inspect(from p in {"users_profiles", Profile}, where: p.author_id in ^[1, 2, 3])
  end

  test "has one custom assoc query" do
    assoc = Post.__schema__(:association, :permalink)
    query = from c in Permalink, limit: 5
    assert inspect(Ecto.Association.Has.assoc_query(assoc, query, [1, 2, 3])) ==
           inspect(from c in Permalink, where: c.post_id in ^[1, 2, 3], limit: 5)
  end

  test "belongs to" do
    assoc = Post.__schema__(:association, :author)

    assert inspect(Ecto.Association.Has.joins_query(assoc)) ==
           inspect(from p in Post, join: a in Author, on: a.id == p.author_id)

    assert inspect(Ecto.Association.Has.assoc_query(assoc, [])) ==
           inspect(from a in Author, where: a.id in ^[])

    assert inspect(Ecto.Association.Has.assoc_query(assoc, [1, 2, 3])) ==
           inspect(from a in Author, where: a.id in ^[1, 2, 3])
  end

  test "belongs to model with specified source" do
    assoc = Email.__schema__(:association, :author)

    assert inspect(Ecto.Association.Has.joins_query(assoc)) ==
           inspect(from e in Email, join: a in {"post_authors", Author}, on: a.id == e.author_id)

    assert inspect(Ecto.Association.Has.assoc_query(assoc, [])) ==
           inspect(from a in {"post_authors", Author}, where: a.id in ^[])

    assert inspect(Ecto.Association.Has.assoc_query(assoc, [1, 2, 3])) ==
           inspect(from a in {"post_authors", Author}, where: a.id in ^[1, 2, 3])
  end

  test "belongs to custom assoc query" do
    assoc = Post.__schema__(:association, :author)
    query = from a in Author, limit: 5
    assert inspect(Ecto.Association.Has.assoc_query(assoc, query, [1, 2, 3])) ==
           inspect(from a in Author, where: a.id in ^[1, 2, 3], limit: 5)
  end

  test "has many through many to many" do
    assoc = Author.__schema__(:association, :posts_comments)

    assert inspect(Ecto.Association.HasThrough.joins_query(assoc)) ==
           inspect(from a in Author, join: p in assoc(a, :posts), join: c in assoc(p, :comments))

    assert inspect(Ecto.Association.HasThrough.assoc_query(assoc, [1,2,3])) ==
           inspect(from c in Comment, join: p in Post, on: p.author_id in ^[1, 2, 3],
                        where: c.post_id == p.id, distinct: true)
  end

  test "has many through many to one" do
    assoc = Author.__schema__(:association, :posts_permalinks)

    assert inspect(Ecto.Association.HasThrough.joins_query(assoc)) ==
           inspect(from a in Author, join: p in assoc(a, :posts), join: c in assoc(p, :permalink))

    assert inspect(Ecto.Association.HasThrough.assoc_query(assoc, [1,2,3])) ==
           inspect(from l in Permalink, join: p in Post, on: p.author_id in ^[1, 2, 3],
                        where: l.post_id == p.id, distinct: true)
  end

  test "has one through belongs to belongs" do
    assoc = Comment.__schema__(:association, :post_author)

    assert inspect(Ecto.Association.HasThrough.joins_query(assoc)) ==
           inspect(from c in Comment, join: p in assoc(c, :post), join: a in assoc(p, :author))

    assert inspect(Ecto.Association.HasThrough.assoc_query(assoc, [1,2,3])) ==
           inspect(from a in Author, join: p in Post, on: p.id in ^[1, 2, 3],
                        where: a.id == p.author_id, distinct: true)
  end

  test "has one through belongs to one" do
    assoc = Comment.__schema__(:association, :post_permalink)

    assert inspect(Ecto.Association.HasThrough.joins_query(assoc)) ==
           inspect(from c in Comment, join: p in assoc(c, :post), join: l in assoc(p, :permalink))

    assert inspect(Ecto.Association.HasThrough.assoc_query(assoc, [1,2,3])) ==
           inspect(from l in Permalink, join: p in Post, on: p.id in ^[1, 2, 3],
                        where: l.post_id == p.id, distinct: true)
  end

  test "has many through one to many" do
    assoc = Summary.__schema__(:association, :post_comments)

    assert inspect(Ecto.Association.HasThrough.joins_query(assoc)) ==
           inspect(from s in Summary, join: p in assoc(s, :post), join: c in assoc(p, :comments))

    assert inspect(Ecto.Association.HasThrough.assoc_query(assoc, [1,2,3])) ==
           inspect(from c in Comment, join: p in Post, on: p.summary_id in ^[1, 2, 3],
                        where: c.post_id == p.id, distinct: true)
  end

  test "has one through one to belongs" do
    assoc = Summary.__schema__(:association, :post_author)

    assert inspect(Ecto.Association.HasThrough.joins_query(assoc)) ==
           inspect(from s in Summary, join: p in assoc(s, :post), join: a in assoc(p, :author))

    assert inspect(Ecto.Association.HasThrough.assoc_query(assoc, [1,2,3])) ==
           inspect(from a in Author, join: p in Post, on: p.summary_id in ^[1, 2, 3],
                        where: a.id == p.author_id, distinct: true)
  end

  test "has many through custom assoc many to many query" do
    assoc = Author.__schema__(:association, :posts_comments)
    query = from c in Comment, where: c.text == "foo", limit: 5
    assert inspect(Ecto.Association.HasThrough.assoc_query(assoc, query, [1,2,3])) ==
           inspect(from c in Comment, join: p in Post,
                        on: p.author_id in ^[1, 2, 3],
                        where: c.post_id == p.id, where: c.text == "foo",
                        distinct: true, limit: 5)

    query = from c in {"custom", Comment}, where: c.text == "foo", limit: 5
    assert inspect(Ecto.Association.HasThrough.assoc_query(assoc, query, [1,2,3])) ==
           inspect(from c in {"custom", Comment}, join: p in Post,
                        on: p.author_id in ^[1, 2, 3],
                        where: c.post_id == p.id, where: c.text == "foo",
                        distinct: true, limit: 5)

    query = from c in Comment, join: p in assoc(c, :permalink), limit: 5
    assert inspect(Ecto.Association.HasThrough.assoc_query(assoc, query, [1,2,3])) ==
           inspect(from c in Comment, join: p0 in Permalink, on: p0.comment_id == c.id,
                        join: p1 in Post, on: p1.author_id in ^[1, 2, 3],
                        where: c.post_id == p1.id,
                        distinct: true, limit: 5)
  end

  ## Integration tests through Ecto

  test "build/2" do
    assert build_assoc(%Post{id: 1}, :comments) ==
           %Comment{post_id: 1}

    assert build_assoc(%Summary{id: 1}, :post) ==
           %Post{summary_id: 1, title: "default"}

    assert_raise ArgumentError, ~r"cannot build belongs_to association :author", fn ->
      assert build_assoc(%Email{id: 1}, :author)
    end

    assert_raise ArgumentError, ~r"cannot build through association :post_author", fn ->
      build_assoc(%Comment{}, :post_author)
    end
  end

  test "build/2 with custom source" do
    email = build_assoc(%Author{id: 1}, :emails)
    assert email.__meta__.source == {nil, "users_emails"}

    profile = build_assoc(%Author{id: 1}, :profile)
    assert profile.__meta__.source == {nil, "users_profiles"}
  end

  test "build/3 with custom attributes" do
    assert build_assoc(%Post{id: 1}, :comments, text: "Awesome!") ==
           %Comment{post_id: 1, text: "Awesome!"}

    assert build_assoc(%Post{id: 1}, :comments, %{text: "Awesome!"}) ==
           %Comment{post_id: 1, text: "Awesome!"}

    assert build_assoc(%Post{id: 1}, :comments, post_id: 2) ==
           %Comment{post_id: 1}

    # Overriding defaults
    assert build_assoc(%Summary{id: 1}, :post, title: "Hello").title == "Hello"

    # Should not allow overriding of __meta__
    meta = %{__meta__: %{source: {nil, "posts"}}}
    comment = build_assoc(%Post{id: 1}, :comments, meta)
    assert comment.__meta__.source == {nil, "comments"}
  end

  test "sets association to loaded/not loaded" do
    refute Ecto.assoc_loaded?(%Post{}.comments)
    assert Ecto.assoc_loaded?(%Post{comments: []}.comments)
  end

  test "assoc/2" do
    assert inspect(assoc(%Post{id: 1}, :comments)) ==
           inspect(from c in Comment, where: c.post_id in ^[1])

    assert inspect(assoc([%Post{id: 1}, %Post{id: 2}], :comments)) ==
           inspect(from c in Comment, where: c.post_id in ^[1, 2])
  end

  test "assoc/2 filters nil ids" do
    assert inspect(assoc([%Post{id: 1}, %Post{id: 2}, %Post{}], :comments)) ==
           inspect(from c in Comment, where: c.post_id in ^[1, 2])
  end

  test "assoc/2 fails on empty list" do
    assert_raise ArgumentError, ~r"cannot retrieve association :whatever for empty list", fn ->
      assoc([], :whatever)
    end
  end

  test "assoc/2 fails on missing association" do
    assert_raise ArgumentError, ~r"does not have association :whatever", fn ->
      assoc([%Post{}], :whatever)
    end
  end

  test "assoc/2 fails on heterogeneous collections" do
    assert_raise ArgumentError, ~r"expected a homogeneous list containing the same struct", fn ->
      assoc([%Post{}, %Comment{}], :comments)
    end
  end

  ## Preloader

  alias Ecto.Repo.Preloader

  test "preload: normalizer" do
    assert Preloader.normalize(:foo, [], []) == [foo: {nil, []}]
    assert Preloader.normalize([foo: :bar], [], []) == [foo: {nil, [bar: {nil, []}]}]
    assert Preloader.normalize([foo: [:bar, baz: :bat], this: :that], [], []) ==
           [this: {nil, [that: {nil, []}]},
            foo: {nil, [baz: {nil, [bat: {nil, []}]},
                        bar: {nil, []}]}]

    query = from(p in Post, limit: 1)
    assert Preloader.normalize([foo: query], [], []) ==
           [foo: {query, []}]
    assert Preloader.normalize([foo: {query, :bar}], [], []) ==
           [foo: {query, [bar: {nil, []}]}]
    assert Preloader.normalize([foo: {query, bar: :baz}], [], []) ==
           [foo: {query, [bar: {nil, [baz: {nil, []}]}]}]
  end

  test "preload: raises on assoc conflict" do
    assert_raise ArgumentError, ~r"cannot preload association `:foo`", fn ->
      Preloader.normalize(:foo, [foo: []], [])
    end
  end

  test "preload: raises on invalid preload" do
    assert_raise ArgumentError, ~r"invalid preload `123` in `123`", fn ->
      Preloader.normalize(123, [], 123)
    end

    assert_raise ArgumentError, ~r"invalid preload `{:bar, :baz}` in", fn ->
      Preloader.normalize([foo: {:bar, :baz}], [], []) == [foo: [bar: []]]
    end
  end

  defp expand(model, preloads) do
    Preloader.expand(model, Preloader.normalize(preloads, [], preloads), [])
  end

  test "preload: expand" do
    assert [{:comments, {:assoc, %Ecto.Association.Has{}, :post_id}, {nil, []}},
            {:permalink, {:assoc, %Ecto.Association.Has{}, :post_id}, {nil, []}}] =
           expand(Post, [:comments, :permalink])

    assert [{:post, {:assoc, %Ecto.Association.BelongsTo{}, :id},
              {nil, [author: {nil, []}, permalink: {nil, []}]}}] =
           expand(Comment, [:post, post: :author, post: :permalink])

    assert [{:post, {:assoc, %Ecto.Association.BelongsTo{}, :id},
             {nil, [author: {nil, []}, permalink: {nil, []}]}}] =
           expand(Comment, [:post, post: :author, post: :permalink])

    assert [{:posts, {:assoc, %Ecto.Association.Has{}, :author_id}, {nil, [comments: {nil, [post: {nil, []}]}]}},
            {:posts_comments, {:through, %Ecto.Association.HasThrough{}, [:posts, :comments]}, {nil, []}}] =
           expand(Author, [posts_comments: :post])

    assert [{:posts, {:assoc, %Ecto.Association.Has{}, :author_id}, {nil, [comments: _, comments: _]}},
           {:posts_comments, {:through, %Ecto.Association.HasThrough{}, [:posts, :comments]}, {nil, []}}] =
           expand(Author, [:posts, posts_comments: :post, posts: [comments: :post]])

    query = from(c in Comment, limit: 1)
    assert [{:permalink, {:assoc, %Ecto.Association.Has{}, :post_id}, {nil, []}},
            {:comments, {:assoc, %Ecto.Association.Has{}, :post_id}, {^query, []}}] =
           expand(Post, [:permalink, comments: query])

    assert [{:posts, {:assoc, %Ecto.Association.Has{}, :author_id}, {nil, [comments: {^query, [post: {nil, []}]}]}},
            {:posts_comments, {:through, %Ecto.Association.HasThrough{}, [:posts, :comments]}, {nil, []}}] =
           expand(Author, [posts_comments: {query, :post}])
  end

  test "preload: expand raises on duplicated entries" do
    message = ~r"cannot preload `comments` as it has been supplied more than once with different queries"
    assert_raise ArgumentError, message, fn ->
      expand(Post, [comments: from(c in Comment, limit: 2),
                    comments: from(c in Comment, limit: 1)])
    end
  end

  ## cast has_one

  test "cast has_one with valid params" do
    changeset = cast(%Author{}, %{"profile" => %{"name" => "michal"}}, :profile)
    profile = changeset.changes.profile
    assert profile.changes == %{name: "michal"}
    assert profile.errors == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast has_one with invalid params" do
    changeset = cast(%Author{}, %{"profile" => %{name: nil}}, :profile)
    assert changeset.changes.profile.changes == %{}
    assert changeset.changes.profile.errors  == [name: "can't be blank"]
    assert changeset.changes.profile.action  == :insert
    refute changeset.changes.profile.valid?
    refute changeset.valid?

    changeset = cast(%Author{}, %{"profile" => "value"}, :profile)
    assert changeset.errors == [profile: "is invalid"]
    refute changeset.valid?
  end

  test "cast has_one with existing model updating" do
    changeset = cast(%Author{profile: %Profile{name: "michal", id: 1}},
                     %{"profile" => %{"name" => "new", "id" => 1}}, :profile)

    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.action  == :update
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast has_one without loading" do
    assert cast(%Author{}, %{"profile" => nil}, :profile).changes == %{}

    loaded = put_in %Author{}.__meta__.state, :loaded
    assert_raise RuntimeError, ~r"attempting to cast or change association `profile` .* that was not loaded", fn ->
      cast(loaded, %{"profile" => nil}, :profile)
    end
  end

  test "cast has_one with existing model replacing" do
    changeset = cast(%Author{profile: %Profile{name: "michal", id: 1}},
                     %{"profile" => %{"name" => "new"}}, :profile)

    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?

    changeset = cast(%Author{profile: %Profile{name: "michal", id: 2}},
                     %{"profile" => %{"name" => "new", "id" => 5}}, :profile)
    profile = changeset.changes.profile
    assert profile.changes == %{name: "new", id: 5}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?

    assert_raise RuntimeError, ~r"cannot update .* it does not exist in the parent model", fn ->
      cast(%Author{profile: %Profile{name: "michal", id: "michal"}},
           %{"profile" => %{"name" => "new", "id" => "new"}},
           :profile, with: &Profile.set_action/2)
    end
  end

  test "cast has_one without changes skips" do
    changeset = cast(%Author{profile: %Profile{name: "michal", id: 1}},
                     %{"profile" => %{"id" => 1}}, :profile)
    assert changeset.changes == %{}
    assert changeset.errors == []

    changeset = cast(%Author{profile: %Profile{name: "michal", id: 1}},
                     %{"profile" => %{"id" => "1"}}, :profile)
    assert changeset.changes == %{}
    assert changeset.errors == []
  end

  test "cast has_one when required" do
    changeset = cast(%Author{}, %{}, :profile, required: true)
    assert changeset.required == [:profile]
    assert changeset.changes == %{}
    assert changeset.errors == [profile: "can't be blank"]

    changeset = cast(%Author{profile: nil}, %{}, :profile, required: true)
    assert changeset.required == [:profile]
    assert changeset.changes == %{}
    assert changeset.errors == [profile: "can't be blank"]

    changeset = cast(%Author{profile: %Profile{}}, %{}, :profile, required: true)
    assert changeset.required == [:profile]
    assert changeset.changes == %{}
    assert changeset.errors == []

    changeset = cast(%Author{profile: nil}, %{"profile" => nil}, :profile, required: true)
    assert changeset.required == [:profile]
    assert changeset.changes == %{}
    assert changeset.errors == [profile: "can't be blank"]

    changeset = cast(%Author{profile: %Profile{}}, %{"profile" => nil}, :profile, required: true)
    assert changeset.required == [:profile]
    assert changeset.changes == %{profile: nil}
    assert changeset.errors == [profile: "can't be blank"]
  end

  test "cast has_one with optional" do
    changeset = cast(%Author{profile: %Profile{id: "id"}}, %{"profile" => nil}, :profile)
    assert changeset.optional == [:profile]
    assert changeset.changes.profile == nil
  end

  test "cast has_one with custom changeset" do
    changeset = cast(%Author{}, %{"profile" => %{}}, :profile, with: &Profile.optional_changeset/2)
    profile = changeset.changes.profile
    assert profile.model.name == "default"
    assert profile.model.__meta__.source == {nil, "users_profiles"}
    assert profile.changes == %{}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast has_one keeps appropriate action from changeset" do
    changeset = cast(%Author{profile: %Profile{id: "id"}},
                     %{"profile" => %{"name" => "michal", "id" => "id"}},
                     :profile, with: &Profile.set_action/2)
    assert changeset.changes.profile.action == :update

    assert_raise RuntimeError, ~r"cannot update .* it does not exist in the parent model", fn ->
      cast(%Author{profile: %Profile{id: "old"}},
           %{"profile" => %{"name" => "michal", "id" => "new"}},
           :profile, with: &Profile.set_action/2)
    end
  end

  test "cast has_one with :empty parameters" do
    changeset = cast(%Author{profile: nil}, :empty, :profile)
    assert changeset.changes == %{}

    changeset = cast(%Author{}, :empty, :profile, required: true)
    assert changeset.changes == %{}

    changeset = cast(%Author{profile: %Profile{}}, :empty, :profile, required: true)
    assert changeset.changes == %{}
  end

  test "cast has_one with on_replace: :raise" do
    model = %Summary{post: %Post{id: 1}}

    params = %{"post" => %{"name" => "jose", "id" => "1"}}
    changeset = cast(model, params, :post, on_replace: :raise)
    assert changeset.changes.post.action == :update

    params = %{"post" => nil}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(model, params, :post, on_replace: :raise)
    end

    params = %{"post" => %{"name" => "new", "id" => 2}}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(model, params, :post, on_replace: :raise)
    end
  end

  test "cast has_one with on_replace: :mark_as_invalid" do
    model = %Summary{post: %Post{id: 1}}

    changeset = cast(model, %{"post" => nil}, :post, on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [post: "is invalid"]
    refute changeset.valid?

    changeset = cast(model, %{"post" => %{"id" => 2}}, :post, on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [post: "is invalid"]
    refute changeset.valid?
  end

  test "cast has_one twice" do
    model = %Author{}
    params = %{profile: %{name: "Bruce Wayne", id: 1}}
    model = cast(model, params, :profile) |> Changeset.apply_changes
    params = %{profile: %{name: "Batman", id: 1}}
    changeset = cast(model, params, :profile)
    changeset = cast(changeset, params, :profile)
    assert changeset.valid?

    model = %Author{}
    params = %{profile: %{name: "Bruce Wayne"}}
    changeset = cast(model, params, :profile)
    changeset = cast(changeset, params, :profile)
    assert changeset.valid?
  end

  ## cast has_many

  test "cast has_many with only new models" do
    changeset = cast(%Author{}, %{"posts" => [%{"title" => "hello"}]}, :posts)
    [post_change] = changeset.changes.posts
    assert post_change.changes == %{title: "hello"}
    assert post_change.errors  == []
    assert post_change.action  == :insert
    assert post_change.valid?
    assert changeset.valid?
  end

  test "cast has_many with map" do
    changeset = cast(%Author{}, %{"posts" => %{0 => %{"title" => "hello"}}}, :posts)
    [post_change] = changeset.changes.posts
    assert post_change.changes == %{title: "hello"}
    assert post_change.errors  == []
    assert post_change.action  == :insert
    assert post_change.valid?
    assert changeset.valid?
  end

  test "cast has_many without loading" do
    assert cast(%Author{}, %{"posts" => []}, :posts).changes == %{}

    loaded = put_in %Author{}.__meta__.state, :loaded
    assert_raise RuntimeError, ~r"attempting to cast or change association `posts` .* that was not loaded", fn ->
      cast(loaded, %{"posts" => []}, :posts)
    end
  end

  # Please note the order is important in this test.
  test "cast has_many changing models" do
    posts = [%Post{title: "first", id: 1},
             %Post{title: "second", id: 2},
             %Post{title: "third", id: 3}]
    params = [%{"title" => "new"},
              %{"id" => 2, "title" => nil},
              %{"id" => 3, "title" => "new name"}]

    changeset = cast(%Author{posts: posts}, %{"posts" => params}, :posts)
    [first, new, second, third] = changeset.changes.posts

    assert first.model.id == 1
    assert first.required == [] # Check for not running changeset function
    assert first.action == :delete
    assert first.valid?

    assert new.changes == %{title: "new"}
    assert new.action == :insert
    assert new.valid?

    assert second.model.id == 2
    assert second.errors == [title: "can't be blank"]
    assert second.action == :update
    refute second.valid?

    assert third.model.id == 3
    assert third.action == :update
    assert third.valid?

    refute changeset.valid?
  end

  test "cast has_many with invalid operation" do
    params = %{"posts" => [%{"id" => 1, "title" => "new"}]}
    assert_raise RuntimeError, ~r"cannot update .* it does not exist in the parent model", fn ->
      cast(%Author{posts: []}, params, :posts, with: &Post.set_action/2)
    end
  end

  test "cast has_many with invalid params" do
    changeset = cast(%Author{}, %{"posts" => "value"}, :posts)
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?

    changeset = cast(%Author{}, %{"posts" => ["value"]}, :posts)
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?

    changeset = cast(%Author{}, %{"posts" => nil}, :posts)
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?

    changeset = cast(%Author{}, %{"posts" => %{"id" => "invalid"}}, :posts)
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?
  end

  test "cast has_many without changes skips" do
    changeset = cast(%Author{posts: [%Post{title: "hello", id: 1}]},
                     %{"posts" => [%{"id" => 1}]}, :posts)

    refute Map.has_key?(changeset.changes, :posts)
  end

  test "cast has_many when required" do
    # Still no error because the loaded association is an empty list
    changeset = cast(%Author{}, %{}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.changes == %{}
    assert changeset.errors == []

    changeset = cast(%Author{posts: []}, %{}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.changes == %{}
    assert changeset.errors == []

    changeset = cast(%Author{posts: []}, %{"posts" => nil}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "is invalid"]
  end

  test "cast has_many with :empty parameters" do
    changeset = cast(%Author{posts: []}, :empty, :posts)
    assert changeset.changes == %{}

    changeset = cast(%Author{}, :empty, :posts)
    assert changeset.changes == %{}

    changeset = cast(%Author{posts: [%Post{}]}, :empty, :posts)
    assert changeset.changes == %{}
  end

  test "cast has_many with on_replace: :raise" do
    model = %Summary{posts: [%Post{id: 1}]}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(model, %{"posts" => []}, :posts, on_replace: :raise)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(model, %{"posts" => [%{"id" => 2}]}, :posts, on_replace: :raise)
    end
  end

  test "cast has_many with on_replace: :mark_as_invalid" do
    model = %Summary{posts: [%Post{id: 1}]}

    changeset = cast(model, %{"posts" => []}, :posts, on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?

    changeset = cast(model, %{"posts" => [%{"id" => 2}]}, :posts, on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?
  end

  test "cast has_many twice" do
    model = %Author{}

    params = %{posts: [%{title: "hello", id: 1}]}
    model = cast(model, params, :posts) |> Changeset.apply_changes
    params = %{posts: []}
    changeset = cast(model, params, :posts)
    changeset = cast(changeset, params, :posts)
    assert changeset.valid?

    model = %Author{}
    params = %{posts: [%{title: "hello"}]}
    changeset = cast(model, params, :posts)
    changeset = cast(changeset, params, :posts)
    assert changeset.valid?
  end

  ## Change

  test "change has_one" do
    assoc = Author.__schema__(:association, :profile)

    assert {:ok, changeset, true, false} =
      Relation.change(assoc, %Profile{name: "michal"}, nil)
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, name: "michal", summary_id: nil, author_id: nil}

    assert {:ok, changeset, true, false} =
      Relation.change(assoc, nil, %Profile{})
    assert changeset.action == :delete

    assoc_model = %Profile{}
    assoc_model_changeset = Changeset.change(assoc_model, name: "michal")

    assert {:ok, changeset, true, false} =
      Relation.change(assoc, assoc_model_changeset, nil)
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, name: "michal", summary_id: nil, author_id: nil}

    assert {:ok, changeset, true, false} =
      Relation.change(assoc, assoc_model_changeset, assoc_model)
    assert changeset.action == :update
    assert changeset.changes == %{name: "michal"}

    empty_changeset = Changeset.change(assoc_model)
    assert {:ok, _, true, true} =
      Relation.change(assoc, empty_changeset, assoc_model)

    assoc_with_id = %Profile{id: 2}
    assert {:ok, _, true, false} =
      Relation.change(assoc, %Profile{id: 1}, assoc_with_id)

    update_changeset = %{Changeset.change(assoc_model) | action: :delete}
    assert_raise RuntimeError, ~r"cannot delete .* it does not exist in the parent model", fn ->
      Relation.change(assoc, update_changeset, assoc_with_id)
    end
  end

  test "change has_one keeps appropriate action from changeset" do
    assoc = Author.__schema__(:association, :profile)
    assoc_model = %Profile{}

    changeset = %{Changeset.change(assoc_model, name: "michal") | action: :insert}

    {:ok, changeset, _, _} = Relation.change(assoc, changeset, nil)
    assert changeset.action == :insert

    changeset = %{changeset | action: :delete}
    assert_raise RuntimeError, ~r"cannot delete .* it does not exist in the parent model", fn ->
      Relation.change(assoc, changeset, nil)
    end

    changeset = %{Changeset.change(assoc_model) | action: :update}
    {:ok, changeset, _, _} = Relation.change(assoc, changeset, assoc_model)
    assert changeset.action == :update

    assoc_model = %{assoc_model | id: 5}
    changeset = %{Changeset.change(assoc_model) | action: :insert}
    assert_raise RuntimeError, ~r"cannot insert .* it already exists in the parent model", fn ->
      Relation.change(assoc, changeset, assoc_model)
    end
  end

  test "change has_one with on_replace: :raise" do
    assoc_model = %Post{id: 1}
    base_changeset = Changeset.change(%Summary{post: assoc_model})

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :post, nil, on_replace: :raise)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :post, %Post{id: 2}, on_replace: :raise)
    end
  end

  test "change has_one with on_replace: :mark_as_invalid" do
    assoc_model = %Post{id: 1}
    base_changeset = Changeset.change(%Summary{post: assoc_model})

    changeset = Changeset.put_assoc(base_changeset, :post, nil, on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [post: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.put_assoc(base_changeset, :post, %Post{id: 2}, on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [post: "is invalid"]
    refute changeset.valid?
  end

  test "change has_many" do
    assoc = Author.__schema__(:association, :posts)

    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, [%Post{title: "hello"}], [])
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, title: "hello", summary_id: nil, author_id: nil}

    assert {:ok, [old_changeset, new_changeset], true, false} =
      Relation.change(assoc, [%Post{id: 1}], [%Post{id: 2}])
    assert old_changeset.action  == :delete
    assert new_changeset.action  == :insert
    assert new_changeset.changes == %{id: 1, title: nil, summary_id: nil, author_id: nil}

    assoc_model_changeset = Changeset.change(%Post{}, title: "hello")

    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, [assoc_model_changeset], [])
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, title: "hello", summary_id: nil, author_id: nil}

    assoc_model = %Post{id: 1}
    assoc_model_changeset = Changeset.change(assoc_model, title: "hello")
    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, [assoc_model_changeset], [assoc_model])
    assert changeset.action == :update
    assert changeset.changes == %{title: "hello"}

    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, [], [assoc_model_changeset])
    assert changeset.action == :delete

    empty_changeset = Changeset.change(assoc_model)
    assert {:ok, _, true, true} =
      Relation.change(assoc, [empty_changeset], [assoc_model])

    new_model_update = %{Changeset.change(%Post{id: 2}) | action: :update}
    assert_raise RuntimeError, ~r"cannot update .* it does not exist in the parent model", fn ->
      Relation.change(assoc, [new_model_update], [assoc_model])
    end

    assert_raise RuntimeError, ~r"use a changeset instead", fn ->
      Relation.change(assoc, [%Post{id: 1, title: "hello"}], [%Post{id: 1}])
    end
  end

  test "change has_many with on_replace: :raise" do
    assoc_model = %Post{id: 1}
    base_changeset = Changeset.change(%Summary{posts: [assoc_model]})

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :posts, [], on_replace: :raise)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :posts, [%Post{id: 2}], on_replace: :raise)
    end
  end

  test "change has_many with on_replace: :mark_as_invalid" do
    assoc_model = %Post{id: 1}
    base_changeset = Changeset.change(%Summary{posts: [assoc_model]})

    changeset = Changeset.put_assoc(base_changeset, :posts, [], on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.put_assoc(base_changeset, :posts, [%Post{id: 2}], on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.put_assoc(base_changeset, :posts, [], on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.put_assoc(base_changeset, :posts, [%Post{id: 2}], on_replace: :mark_as_invalid)
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?
  end

  ## Other

  test "put_assoc/4" do
    base_changeset = Changeset.change(%Author{})

    changeset = Changeset.put_assoc(base_changeset, :profile, %Profile{name: "michal"})
    assert %Ecto.Changeset{} = changeset.changes.profile

    base_changeset = Changeset.change(%Author{profile: %Profile{name: "michal"}})
    empty_update_changeset = Changeset.change(%Profile{name: "michal"})

    changeset = Changeset.put_assoc(base_changeset, :profile, empty_update_changeset)
    refute Map.has_key?(changeset.changes, :profile)
  end

  test "get_field/3, fetch_field/2 with assocs" do
    profile_changeset = Changeset.change(%Profile{}, name: "michal")
    profile = Changeset.apply_changes(profile_changeset)

    changeset =
      %Author{}
      |> Changeset.change
      |> Changeset.put_assoc(:profile, profile_changeset)
    assert Changeset.get_field(changeset, :profile) == profile
    assert Changeset.fetch_field(changeset, :profile) == {:changes, profile}

    changeset = Changeset.change(%Author{profile: profile})
    assert Changeset.get_field(changeset, :profile) == profile
    assert Changeset.fetch_field(changeset, :profile) == {:model, profile}

    post = %Post{id: 1}
    post_changeset = %{Changeset.change(post) | action: :delete}
    changeset =
      %Author{posts: [post]}
      |> Changeset.change
      |> Changeset.put_assoc(:posts, [post_changeset])
    assert Changeset.get_field(changeset, :posts) == []
    assert Changeset.fetch_field(changeset, :posts) == {:changes, []}
  end

  test "on_replace: :nilify" do
    # one case is handled inside repo
    post = %Post{id: 1, summary_id: 5}
    changeset = cast(%Summary{post: post}, %{"post" => nil}, :post)
    assert changeset.changes.post == nil

    changeset = cast(%Summary{posts: [post]}, %{"posts" => []}, :posts)
    [post_change] = changeset.changes.posts
    assert post_change.action == :update
    assert post_change.changes == %{summary_id: nil}
  end

  test "apply_changes" do
    embed = Author.__schema__(:association, :profile)

    changeset = Changeset.change(%Profile{}, name: "michal")
    model = Relation.apply_changes(embed, changeset)
    assert model == %Profile{name: "michal"}

    changeset = Changeset.change(%Post{}, title: "hello")
    changeset2 = %{changeset | action: :delete}
    assert Relation.apply_changes(embed, changeset2) == nil

    embed = Author.__schema__(:association, :posts)
    [model] = Relation.apply_changes(embed, [changeset, changeset2])
    assert model == %Post{title: "hello"}
  end

  ## traverse_errors

  test "traverses changeset errors with has_one error" do
    params = %{"title" => "hi", "permalink" => %{"url" => "hi"}}
    changeset =
      %Post{}
      |> Changeset.cast(params, ~w(), ~w(title))
      |> Changeset.cast_assoc(:permalink)
      |> Changeset.add_error(:title, "is invalid")

    errors = Changeset.traverse_errors(changeset, fn
      {err, opts} ->
        err
        |> String.replace("%{count}", to_string(opts[:count]))
        |> String.upcase()
      err ->
        String.upcase(err)
    end)

    assert errors == %{
      permalink: %{url: ["SHOULD BE AT LEAST 3 CHARACTER(S)"]},
      title: ["IS INVALID"]
    }
  end

  test "traverses changeset errors with has_many errors" do
    params = %{"title" => "hi", "permalinks" => [%{"url" => "hi"},
                                                 %{"url" => "valid"}]}
    changeset =
      %Post{}
      |> Changeset.cast(params, ~w(), ~w(title))
      |> Changeset.cast_assoc(:permalinks)
      |> Changeset.add_error(:title, "is invalid")

    errors = Changeset.traverse_errors(changeset, fn
      {err, opts} ->
        err
        |> String.replace("%{count}", to_string(opts[:count]))
        |> String.upcase()
      err ->
        String.upcase(err)
    end)

    assert errors == %{
      permalinks: [%{url: ["SHOULD BE AT LEAST 3 CHARACTER(S)"]}, %{}],
      title: ["IS INVALID"]
    }
  end
end
