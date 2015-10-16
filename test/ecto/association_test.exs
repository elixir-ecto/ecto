defmodule Ecto.AssociationTest do
  use ExUnit.Case, async: true
  doctest Ecto.Association

  import Ecto.Model
  import Ecto.Query, only: [from: 2]
  alias Ecto.Changeset.Relation

  alias __MODULE__.Author
  alias __MODULE__.Comment
  alias __MODULE__.Permalink
  alias __MODULE__.Post
  alias __MODULE__.Summary
  alias __MODULE__.Email
  alias __MODULE__.Profile

  defmodule Post do
    use Ecto.Model

    schema "posts" do
      field :title, :string

      has_many :comments, Comment
      has_one :permalink, Permalink
      belongs_to :author, Author
      belongs_to :summary, Summary
    end

    def changeset(model, params) do
      cast(model, params, ~w(title), ~w(author_id))
    end

    def optional_changeset(model, params) do
      cast(model, params, ~w(), ~w(title author_id))
    end

    def set_action(model, params) do
      cast(model, params, ~w(title))
      |> Map.put(:action, :update)
    end
  end

  defmodule Comment do
    use Ecto.Model

    schema "comments" do
      field :text, :string

      belongs_to :post, Post
      has_one :permalink, Permalink
      has_one :post_author, through: [:post, :author]       # belongs -> belongs
      has_one :post_permalink, through: [:post, :permalink] # belongs -> one
    end
  end

  defmodule Permalink do
    use Ecto.Model

    schema "permalinks" do
    end
  end

  defmodule Author do
    use Ecto.Model

    schema "authors" do
      field :title, :string
      has_many :posts, Post, on_replace: :delete
      has_many :posts_comments, through: [:posts, :comments]    # many -> many
      has_many :posts_permalinks, through: [:posts, :permalink] # many -> one
      has_many :emails, {"users_emails", Email}
      has_one :profile, {"users_profiles", Profile}, on_cast: :required_changeset,
        defaults: [name: "default"], on_replace: :delete
    end
  end

  defmodule Summary do
    use Ecto.Model

    schema "summaries" do
      has_one :post, Post, defaults: [title: "default"], on_replace: :nilify
      has_many :profiles, Profile, on_replace: :nilify
      has_one :raise_profile, Profile
      has_many :raise_posts, Post
      has_one :invalid_profile, Profile, on_replace: :mark_as_invalid
      has_many :invalid_posts, Post, on_replace: :mark_as_invalid
      has_one :post_author, through: [:post, :author]        # one -> belongs
      has_many :post_comments, through: [:post, :comments]   # one -> many
    end
  end

  defmodule Email do
    use Ecto.Model

    schema "emails" do
      belongs_to :author, {"post_authors", Author}
    end
  end

  defmodule Profile do
    use Ecto.Model

    schema "profiles" do
      field :name
      belongs_to :author, Author
      belongs_to :summary, Summary
    end

    def changeset(model, params) do
      cast(model, params, ~w(name))
    end

    def required_changeset(model, params) do
      cast(model, params, ~w(name), ~w(id))
    end

    def optional_changeset(model, params) do
      cast(model, params, ~w(), ~w(name))
    end

    def set_action(model, params) do
      cast(model, params, ~w(name), ~w(id))
      |> Map.put(:action, :update)
    end
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

  ## Integration tests through Ecto.Model

  test "build/2" do
    assert build(%Post{id: 1}, :comments) ==
           %Comment{post_id: 1}

    assert build(%Summary{id: 1}, :post) ==
           %Post{summary_id: 1, title: "default"}

    assert_raise ArgumentError, ~r"cannot build belongs_to association :author", fn ->
      assert build(%Email{id: 1}, :author)
    end

    assert_raise ArgumentError, ~r"cannot build through association :post_author", fn ->
      build(%Comment{}, :post_author)
    end
  end

  test "build/2 with custom source" do
    email = build(%Author{id: 1}, :emails)
    assert email.__meta__.source == {nil, "users_emails"}

    profile = build(%Author{id: 1}, :profile)
    assert profile.__meta__.source == {nil, "users_profiles"}
  end

  test "build/3 with custom attributes" do
    assert build(%Post{id: 1}, :comments, text: "Awesome!") ==
           %Comment{post_id: 1, text: "Awesome!"}

    assert build(%Post{id: 1}, :comments, %{text: "Awesome!"}) ==
           %Comment{post_id: 1, text: "Awesome!"}

    assert build(%Post{id: 1}, :comments, post_id: 2) ==
           %Comment{post_id: 1}

    # Overriding defaults
    assert build(%Summary{id: 1}, :post, title: "Hello").title == "Hello"
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

  test "Ecto.Association.loaded?/1 returns false if association is not loaded" do
    refute Ecto.Association.loaded?(%Post{}.comments)
  end

  test "Ecto.Association.loaded?/1 returns true if association is loaded" do
    assert Ecto.Association.loaded?(%Post{comments: []}.comments)
  end

  ## Preloader

  alias Ecto.Repo.Preloader

  test "preload: normalizer" do
    assert Preloader.normalize(:foo, [], []) == [foo: []]
    assert Preloader.normalize([foo: :bar], [], []) == [foo: [bar: []]]
    assert Preloader.normalize([foo: [:bar, baz: :bat], this: :that], [], []) ==
           [this: [that: []], foo: [baz: [bat: []], bar: []]]

    query = from(p in Post, limit: 1)
    assert Preloader.normalize([foo: query], [], []) == [foo: query]
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
  end

  defp expand(model, preloads) do
    Preloader.expand(model, Preloader.normalize(preloads, [], preloads), [])
  end

  test "preload: expand" do
    assert [{:comments, {:assoc, %Ecto.Association.Has{}, :post_id}, []},
            {:permalink, {:assoc, %Ecto.Association.Has{}, :post_id}, []}] =
           expand(Post, [:comments, :permalink])

    assert [{:post, {:assoc, %Ecto.Association.BelongsTo{}, :id},
              [author: [], permalink: []]}] =
           expand(Comment, [:post, post: :author, post: :permalink])

    assert [{:post, {:assoc, %Ecto.Association.BelongsTo{}, :id},
             [author: [], permalink: []]}] =
           expand(Comment, [:post, post: :author, post: :permalink])

    assert [{:posts, {:assoc, %Ecto.Association.Has{}, :author_id}, [comments: [post: []]]},
            {:posts_comments, {:through, %Ecto.Association.HasThrough{}, [:posts, :comments]}, []}] =
           expand(Author, [posts_comments: :post])

    assert [{:posts, {:assoc, %Ecto.Association.Has{}, :author_id}, [comments: _, comments: _]},
           {:posts_comments, {:through, %Ecto.Association.HasThrough{}, [:posts, :comments]}, []}] =
           expand(Author, [:posts, posts_comments: :post, posts: [comments: :post]])

    query = from(c in Comment, limit: 1)
    assert [{:permalink, {:assoc, %Ecto.Association.Has{}, :post_id}, []},
            {:comments, {:assoc, %Ecto.Association.Has{}, :post_id}, ^query}] =
           expand(Post, [:permalink, comments: query])
  end

  test "preload: expand raises on duplicated entries" do
    message = ~r"cannot preload `comments` as it has been supplied more than once with different argument types"
    assert_raise ArgumentError, message, fn ->
      expand(Post, [comments: [], comments: from(c in Comment, limit: 1)])
    end
  end

  ## cast has_one

  alias Ecto.Changeset

  test "cast has_one with valid params" do
    changeset = Changeset.cast(%Author{}, %{"profile" => %{"name" => "michal"}}, ~w(profile))
    profile = changeset.changes.profile
    assert changeset.required == [:profile]
    assert profile.changes == %{name: "michal"}
    assert profile.errors == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast has_one with invalid params" do
    changeset = Changeset.cast(%Author{}, %{"profile" => %{name: nil}}, ~w(profile))
    assert changeset.changes.profile.changes == %{}
    assert changeset.changes.profile.errors  == [name: "can't be blank"]
    assert changeset.changes.profile.action  == :insert
    refute changeset.changes.profile.valid?
    refute changeset.valid?

    changeset = Changeset.cast(%Author{}, %{"profile" => "value"}, ~w(profile))
    assert changeset.errors == [profile: "is invalid"]
    refute changeset.valid?
  end

  test "cast has_one with existing model updating" do
    changeset =
      Changeset.cast(%Author{profile: %Profile{name: "michal", id: 1}},
                     %{"profile" => %{"name" => "new", "id" => 1}}, ~w(profile))

    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.action  == :update
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast has_one without loading" do
    assert Changeset.cast(%Author{}, %{"profile" => nil}, ~w(profile)).changes == %{}

    loaded = put_in %Author{}.__meta__.state, :loaded
    assert_raise ArgumentError, ~r"attempting to cast or change association `profile` .* that was not loaded", fn ->
      Changeset.cast(loaded, %{"profile" => nil}, ~w(profile))
    end
  end

  test "cast has_one with existing model replacing" do
    changeset =
      Changeset.cast(%Author{profile: %Profile{name: "michal", id: 1}},
                     %{"profile" => %{"name" => "new"}}, ~w(profile))

    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?

    changeset =
      Changeset.cast(%Author{profile: %Profile{name: "michal", id: 2}},
                     %{"profile" => %{"name" => "new", "id" => 5}}, ~w(profile))
    profile = changeset.changes.profile
    assert profile.changes == %{name: "new", id: 5}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?

    assert_raise RuntimeError, ~r"cannot update .* it does not exist in the parent model", fn ->
      Changeset.cast(%Author{profile: %Profile{name: "michal", id: "michal"}},
                     %{"profile" => %{"name" => "new", "id" => "new"}},
                     profile: :set_action)
    end
  end

  test "cast has_one without changes skips" do
    changeset =
      Changeset.cast(%Author{profile: %Profile{name: "michal", id: 1}},
                     %{"profile" => %{"id" => 1}}, ~w(profile))
    assert changeset.changes == %{}
    assert changeset.errors == []

    changeset =
      Changeset.cast(%Author{profile: %Profile{name: "michal", id: 1}},
                     %{"profile" => %{"id" => "1"}}, ~w(profile))
    assert changeset.changes == %{}
    assert changeset.errors == []
  end

  test "cast has_one when required" do
    changeset =
      Changeset.cast(%Author{}, %{}, ~w(profile))
    assert changeset.changes == %{}
    assert changeset.errors == [profile: "can't be blank"]

    changeset =
      Changeset.cast(%Author{profile: nil}, %{}, ~w(profile))
    assert changeset.changes == %{}
    assert changeset.errors == [profile: "can't be blank"]

    changeset =
      Changeset.cast(%Author{profile: %Profile{}}, %{}, ~w(profile))
    assert changeset.changes == %{}
    assert changeset.errors == []

    changeset =
      Changeset.cast(%Author{profile: nil}, %{"profile" => nil}, ~w(profile))
    assert changeset.changes == %{}
    assert changeset.errors == [profile: "can't be blank"]

    changeset =
      Changeset.cast(%Author{profile: %Profile{}}, %{"profile" => nil}, ~w(profile))
    assert changeset.changes == %{}
    assert changeset.errors == [profile: "can't be blank"]
  end

  test "cast has_one with optional" do
    changeset = Changeset.cast(%Author{profile: %Profile{id: "id"}},
                               %{"profile" => nil},
                               [], ~w(profile))
    assert changeset.changes.profile == nil
  end

  test "cast has_one with custom changeset" do
    changeset = Changeset.cast(%Author{}, %{"profile" => %{"name" => "michal"}},
                     [profile: :optional_changeset])
    profile = changeset.changes.profile
    assert changeset.required == [:profile]
    assert profile.model.name == "default"
    assert profile.model.__meta__.source == {nil, "users_profiles"}
    assert profile.changes == %{name: "michal"}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?

    changeset = Changeset.cast(%Author{}, %{"profile" => %{}}, [profile: :optional_changeset])
    profile = changeset.changes.profile
    assert changeset.required == [:profile]
    assert profile.model.name == "default"
    assert profile.model.__meta__.source == {nil, "users_profiles"}
    assert profile.changes == %{}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast has_one keeps appropriate action from changeset" do
    changeset = Changeset.cast(%Author{profile: %Profile{id: "id"}},
                               %{"profile" => %{"name" => "michal", "id" => "id"}},
                               [profile: :set_action])
    assert changeset.changes.profile.action == :update

    assert_raise RuntimeError, ~r"cannot update .* it does not exist in the parent model", fn ->
      Changeset.cast(%Author{profile: %Profile{id: "old"}},
                     %{"profile" => %{"name" => "michal", "id" => "new"}},
                     [profile: :set_action])
    end
  end

  test "cast has_one with :empty parameters" do
    changeset = Changeset.cast(%Author{profile: nil}, :empty, profile: :optional_changeset)
    assert changeset.changes == %{}

    changeset = Changeset.cast(%Author{}, :empty, ~w(profile))
    assert changeset.changes == %{}

    changeset = Changeset.cast(%Author{profile: %Profile{}}, :empty, profile: :optional_changeset)
    assert changeset.changes == %{}
  end

  test "cast has_one with on_replace: :raise" do
    model = %Summary{raise_profile: %Profile{id: 1}}

    params = %{"raise_profile" => %{"name" => "jose", "id" => "1"}}
    changeset = Changeset.cast(model, params, [:raise_profile])
    assert changeset.changes.raise_profile.action == :update

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.cast(model, %{"raise_profile" => nil}, [], [:raise_profile])
    end

    params = %{"raise_profile" => %{"name" => "new", "id" => 2}}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.cast(model, params, [:raise_profile])
    end
  end

  test "cast has_one with on_replace: :mark_as_invalid" do
    model = %Summary{invalid_profile: %Profile{id: 1}}

    changeset = Changeset.cast(model, %{"invalid_profile" => nil},
                               [], [:invalid_profile])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.cast(model, %{"invalid_profile" => %{"id" => 2}},
                               [:invalid_profile])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: "is invalid"]
    refute changeset.valid?
  end

  test "cast has_one twice" do
    model = %Author{}
    params = %{profile: %{name: "Bruce Wayne", id: 1}}
    model = Changeset.cast(model, params, ~w(), ~w(profile)) |> Changeset.apply_changes
    params = %{profile: %{name: "Batman", id: 1}}
    changeset = Changeset.cast(model, params, ~w(), ~w(profile))
    changeset = Changeset.cast(changeset, params, ~w(), ~w(profile))
    assert changeset.valid?

    model = %Author{}
    params = %{profile: %{name: "Bruce Wayne"}}
    changeset = Changeset.cast(model, params, ~w(), ~w(profile))
    changeset = Changeset.cast(changeset, params, ~w(), ~w(profile))
    assert changeset.valid?
  end

  ## cast has_many

  test "cast has_many with only new models" do
    changeset = Changeset.cast(%Author{}, %{"posts" => [%{"title" => "hello"}]}, ~w(posts))
    [post_change] = changeset.changes.posts
    assert post_change.changes == %{title: "hello"}
    assert post_change.errors  == []
    assert post_change.action  == :insert
    assert post_change.valid?
    assert changeset.valid?
  end

  test "cast has_many with map" do
    changeset = Changeset.cast(%Author{}, %{"posts" => %{0 => %{"title" => "hello"}}}, ~w(posts))
    [post_change] = changeset.changes.posts
    assert post_change.changes == %{title: "hello"}
    assert post_change.errors  == []
    assert post_change.action  == :insert
    assert post_change.valid?
    assert changeset.valid?
  end

  test "cast has_many with custom changeset" do
    changeset = Changeset.cast(%Author{}, %{"posts" => [%{"title" => "hello"}]},
                               [posts: :optional_changeset])
    [post_change] = changeset.changes.posts
    assert post_change.changes == %{title: "hello"}
    assert post_change.errors  == []
    assert post_change.action  == :insert
    assert post_change.valid?
    assert changeset.valid?
  end

  test "cast has_many without loading" do
    assert Changeset.cast(%Author{}, %{"posts" => []}, ~w(posts)).changes == %{}

    loaded = put_in %Author{}.__meta__.state, :loaded
    assert_raise ArgumentError, ~r"attempting to cast or change association `posts` .* that was not loaded", fn ->
      Changeset.cast(loaded, %{"posts" => []}, ~w(posts))
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

    changeset = Changeset.cast(%Author{posts: posts}, %{"posts" => params}, ~w(posts))
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
      Changeset.cast(%Author{posts: []}, params, [posts: :set_action])
    end
  end

  test "cast has_many with invalid params" do
    changeset = Changeset.cast(%Author{}, %{"posts" => "value"}, ~w(posts))
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.cast(%Author{}, %{"posts" => ["value"]}, ~w(posts))
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.cast(%Author{}, %{"posts" => nil}, ~w(posts))
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.cast(%Author{}, %{"posts" => %{"id" => "invalid"}}, ~w(posts))
    assert changeset.errors == [posts: "is invalid"]
    refute changeset.valid?
  end

  test "cast has_many without changes skips" do
    changeset =
      Changeset.cast(%Author{posts: [%Post{title: "hello", id: 1}]},
                     %{"posts" => [%{"id" => 1}]}, ~w(posts))

    refute Map.has_key?(changeset.changes, :posts)
  end

  test "cast has_many when required" do
    # Still no error because the loaded association is an empty list
    changeset =
      Changeset.cast(%Author{}, %{}, ~w(posts))
    assert changeset.changes == %{}
    assert changeset.errors == []

    changeset =
      Changeset.cast(%Author{posts: []}, %{}, ~w(posts))
    assert changeset.changes == %{}
    assert changeset.errors == []

    changeset =
      Changeset.cast(%Author{posts: []}, %{"posts" => nil}, ~w(posts))
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "is invalid"]
  end

  test "cast has_many with :empty parameters" do
    changeset = Changeset.cast(%Author{posts: []}, :empty, ~w(posts))
    assert changeset.changes == %{}

    changeset = Changeset.cast(%Author{}, :empty, ~w(posts))
    assert changeset.changes == %{}

    changeset = Changeset.cast(%Author{posts: [%Post{}]}, :empty, ~w(posts))
    assert changeset.changes == %{}
  end

  test "cast has_many with on_replace: :raise" do
    model = %Summary{raise_posts: [%Post{id: 1}]}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.cast(model, %{"raise_posts" => []}, [:raise_posts])
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.cast(model, %{"raise_posts" => [%{"id" => 2}]}, [:raise_posts])
    end
  end

  test "cast has_many with on_replace: :mark_as_invalid" do
    model = %Summary{invalid_posts: [%Post{id: 1}]}

    changeset = Changeset.cast(model, %{"invalid_posts" => []}, [:invalid_posts])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.cast(model, %{"invalid_posts" => [%{"id" => 2}]},
                               [:invalid_posts])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: "is invalid"]
    refute changeset.valid?
  end

  test "cast has_many twice" do
    model = %Author{}

    params = %{posts: [%{title: "hello", id: 1}]}
    model = Changeset.cast(model, params, ~w(), ~w(posts)) |> Changeset.apply_changes
    params = %{posts: []}
    changeset = Changeset.cast(model, params, ~w(), ~w(posts))
    changeset = Changeset.cast(changeset, params, ~w(), ~w(posts))
    assert changeset.valid?

    model = %Author{}
    params = %{posts: [%{title: "hello"}]}
    changeset = Changeset.cast(model, params, ~w(), ~w(posts))
    changeset = Changeset.cast(changeset, params, ~w(), ~w(posts))
    assert changeset.valid?
  end

  ## Change

  test "change has_one" do
    model = %Author{}
    assoc = Author.__schema__(:association, :profile)

    assert {:ok, changeset, true, false} =
      Relation.change(assoc, model, %Profile{name: "michal"}, nil)
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, name: "michal", summary_id: nil, author_id: nil}

    assert {:ok, changeset, true, false} =
      Relation.change(assoc, model, %Profile{name: "michal"}, %Profile{})
    assert changeset.action == :update
    assert changeset.changes == %{name: "michal"}

    assert {:ok, changeset, true, false} =
      Relation.change(assoc, model, nil, %Profile{})
    assert changeset.action == :delete

    assoc_model = %Profile{}
    assoc_model_changeset = Changeset.change(assoc_model, name: "michal")

    assert {:ok, changeset, true, false} =
      Relation.change(assoc, model, assoc_model_changeset, nil)
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, name: "michal", summary_id: nil, author_id: nil}

    assert {:ok, changeset, true, false} =
      Relation.change(assoc, model, assoc_model_changeset, assoc_model)
    assert changeset.action == :update
    assert changeset.changes == %{name: "michal"}

    empty_changeset = Changeset.change(assoc_model)
    assert {:ok, _, true, true} =
      Relation.change(assoc, model, empty_changeset, assoc_model)

    assoc_with_id = %Profile{id: 2}
    assert {:ok, _, true, false} =
      Relation.change(assoc, model, %Profile{id: 1}, assoc_with_id)

    update_changeset = %{Changeset.change(assoc_model) | action: :delete}
    assert_raise RuntimeError, ~r"cannot delete .* it does not exist in the parent model", fn ->
      Relation.change(assoc, model, update_changeset, assoc_with_id)
    end
  end

  test "change has_one keeps appropriate action from changeset" do
    model = %Author{}
    assoc = Author.__schema__(:association, :profile)
    assoc_model = %Profile{}

    changeset = %{Changeset.change(assoc_model, name: "michal") | action: :insert}

    {:ok, changeset, _, _} = Relation.change(assoc, model, changeset, nil)
    assert changeset.action == :insert

    changeset = %{changeset | action: :delete}
    assert_raise RuntimeError, ~r"cannot delete .* it does not exist in the parent model", fn ->
      Relation.change(assoc, model, changeset, nil)
    end

    changeset = %{Changeset.change(assoc_model) | action: :update}
    {:ok, changeset, _, _} = Relation.change(assoc, model, changeset, assoc_model)
    assert changeset.action == :update

    assoc_model = %{assoc_model | id: 5}
    model = %{model | profile: assoc_model}
    changeset = %{Changeset.change(assoc_model) | action: :insert}
    assert_raise RuntimeError, ~r"cannot insert .* it already exists in the parent model", fn ->
      Relation.change(assoc, model, changeset, assoc_model)
    end
  end

  test "change has_one with on_replace: :raise" do
    model = %Summary{}
    assoc = Summary.__schema__(:association, :raise_profile)
    assoc_model = %Profile{id: 1}

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Relation.change(assoc, model, nil, assoc_model)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Relation.change(assoc, model, %Profile{id: 2}, assoc_model)
    end
  end

  test "change has_one with on_replace: :mark_as_invalid" do
    model = %Summary{}
    assoc = Summary.__schema__(:association, :invalid_profile)
    assoc_model = %Profile{id: 1}

    assert :error == Relation.change(assoc, model, nil, assoc_model)
    assert :error == Relation.change(assoc, model, %Profile{id: 2}, assoc_model)

    base_changeset = Changeset.change(%Summary{invalid_profile: assoc_model})

    changeset = Changeset.change(base_changeset, invalid_profile: nil)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.change(base_changeset, invalid_profile: %Profile{id: 2})
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.put_change(base_changeset, :invalid_profile, nil)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.put_change(base_changeset, :invalid_profile, %Profile{id: 2})
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: "is invalid"]
    refute changeset.valid?
  end

  test "change has_many" do
    model = %Author{}
    assoc = Author.__schema__(:association, :posts)

    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, model, [%Post{title: "hello"}], [])
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, title: "hello", summary_id: nil, author_id: nil}

    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, model, [%Post{id: 1, title: "hello"}], [%Post{id: 1}])
    assert changeset.action == :update
    assert changeset.changes == %{title: "hello"}

    assert {:ok, [old_changeset, new_changeset], true, false} =
      Relation.change(assoc, model, [%Post{id: 1}], [%Post{id: 2}])
    assert old_changeset.action  == :delete
    assert new_changeset.action  == :insert
    assert new_changeset.changes == %{id: 1, title: nil, summary_id: nil, author_id: nil}

    assoc_model_changeset = Changeset.change(%Post{}, title: "hello")

    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, model, [assoc_model_changeset], [])
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, title: "hello", summary_id: nil, author_id: nil}

    assoc_model = %Post{id: 1}
    assoc_model_changeset = Changeset.change(assoc_model, title: "hello")
    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, model, [assoc_model_changeset], [assoc_model])
    assert changeset.action == :update
    assert changeset.changes == %{title: "hello"}

    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, model, [], [assoc_model_changeset])
    assert changeset.action == :delete

    empty_changeset = Changeset.change(assoc_model)
    assert {:ok, _, true, true} =
      Relation.change(assoc, model, [empty_changeset], [assoc_model])

    new_model_update = %{Changeset.change(%Post{id: 2}) | action: :update}
    assert_raise RuntimeError, ~r"cannot update .* it does not exist in the parent model", fn ->
      Relation.change(assoc, model, [new_model_update], [assoc_model])
    end
  end

  test "change has_many with on_replace: :raise" do
    model = %Summary{}
    assoc = Summary.__schema__(:association, :raise_posts)
    assoc_model = %Post{id: 1}

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Relation.change(assoc, model, [], [assoc_model])
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Relation.change(assoc, model, [%Post{id: 2}], [assoc_model])
    end
  end

  test "change has_many with on_replace: :mark_as_invalid" do
    model = %Summary{}
    assoc = Summary.__schema__(:association, :invalid_posts)
    assoc_model = %Post{id: 1}

    assert :error == Relation.change(assoc, model, [], [assoc_model])
    assert :error == Relation.change(assoc, model, [%Post{id: 2}], [assoc_model])

    base_changeset = Changeset.change(%Summary{invalid_posts: [assoc_model]})

    changeset = Changeset.change(base_changeset, invalid_posts: [])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.change(base_changeset, invalid_posts: [%Post{id: 2}])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.put_change(base_changeset, :invalid_posts, [])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.put_change(base_changeset, :invalid_posts, [%Post{id: 2}])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: "is invalid"]
    refute changeset.valid?
  end

  ## Other

  test "change/2, put_change/3, force_change/3 wth assocs" do
    base_changeset = Changeset.change(%Author{})

    changeset = Changeset.change(base_changeset, profile: %Profile{name: "michal"})
    assert %Ecto.Changeset{} = changeset.changes.profile

    changeset = Changeset.put_change(base_changeset, :profile, %Profile{name: "michal"})
    assert %Ecto.Changeset{} = changeset.changes.profile

    changeset = Changeset.force_change(base_changeset, :profile, %Profile{name: "michal"})
    assert %Ecto.Changeset{} = changeset.changes.profile

    base_changeset = Changeset.change(%Author{profile: %Profile{name: "michal"}})
    empty_update_changeset = Changeset.change(%Profile{name: "michal"})

    changeset = Changeset.put_change(base_changeset, :profile, empty_update_changeset)
    assert changeset.changes == %{}

    changeset = Changeset.force_change(base_changeset, :profile, empty_update_changeset)
    assert %Ecto.Changeset{} = changeset.changes.profile
  end

  test "get_field/3, fetch_field/2 with assocs" do
    profile_changeset = Changeset.change(%Profile{}, name: "michal")
    profile = Changeset.apply_changes(profile_changeset)

    changeset = Changeset.change(%Author{}, profile: profile_changeset)
    assert Changeset.get_field(changeset, :profile) == profile
    assert Changeset.fetch_field(changeset, :profile) == {:changes, profile}

    changeset = Changeset.change(%Author{profile: profile})
    assert Changeset.get_field(changeset, :profile) == profile
    assert Changeset.fetch_field(changeset, :profile) == {:model, profile}

    post = %Post{id: 1}
    post_changeset = %{Changeset.change(post) | action: :delete}
    changeset = Changeset.change(%Author{posts: [post]}, posts: [post_changeset])
    assert Changeset.get_field(changeset, :posts) == []
    assert Changeset.fetch_field(changeset, :posts) == {:changes, []}
  end

  test "on_replace: :nilify" do
    # one case is handled inside repo
    post = %Post{id: 1, summary_id: 5}
    changeset = Changeset.cast(%Summary{post: post}, %{"post" => nil}, ~w(), ~w(post))
    assert changeset.changes.post == nil

    profile = %Profile{id: 1, summary_id: 3}
    changeset = Changeset.cast(%Summary{profiles: [profile]}, %{"profiles" => []}, ~w(profiles))
    [profile_change] = changeset.changes.profiles
    assert profile_change.action == :update
    assert profile_change.changes == %{summary_id: nil}
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
end
