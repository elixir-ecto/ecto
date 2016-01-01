defmodule Ecto.AssociationTest do
  use ExUnit.Case, async: true
  doctest Ecto.Association

  import Ecto
  import Ecto.Query, only: [from: 2]

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
      belongs_to :author, Author, defaults: [title: "World!"]
      belongs_to :summary, Summary
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
      many_to_many :authors, Author, join_through: "authors_permalinks", defaults: [title: "m2m!"]
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
      many_to_many :permalinks, {"custom_permalinks", Permalink},
        join_through: "authors_permalinks"
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
  end

  test "has many" do
    assoc = Post.__schema__(:association, :comments)

    assert inspect(Ecto.Association.Has.joins_query(assoc)) ==
           inspect(from p in Post, join: c in Comment, on: c.post_id == p.id)

    assert inspect(Ecto.Association.Has.assoc_query(assoc, nil, [])) ==
           inspect(from c in Comment, where: c.post_id in ^[])

    assert inspect(Ecto.Association.Has.assoc_query(assoc, nil, [1, 2, 3])) ==
           inspect(from c in Comment, where: c.post_id in ^[1, 2, 3])
  end

  test "has many with specified source" do
    assoc = Author.__schema__(:association, :emails)

    assert inspect(Ecto.Association.Has.joins_query(assoc)) ==
           inspect(from a in Author, join: e in {"users_emails", Email}, on: e.author_id == a.id)

    assert inspect(Ecto.Association.Has.assoc_query(assoc, nil, [])) ==
           inspect(from e in {"users_emails", Email}, where: e.author_id in ^[])

    assert inspect(Ecto.Association.Has.assoc_query(assoc, nil, [1, 2, 3])) ==
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

    assert inspect(Ecto.Association.Has.assoc_query(assoc, nil, [])) ==
           inspect(from c in Permalink, where: c.post_id in ^[])

    assert inspect(Ecto.Association.Has.assoc_query(assoc, nil, [1, 2, 3])) ==
           inspect(from c in Permalink, where: c.post_id in ^[1, 2, 3])
  end

  test "has one with specified source" do
    assoc = Author.__schema__(:association, :profile)

    assert inspect(Ecto.Association.Has.joins_query(assoc)) ==
           inspect(from a in Author, join: p in {"users_profiles", Profile}, on: p.author_id == a.id)

    assert inspect(Ecto.Association.Has.assoc_query(assoc, nil, [])) ==
           inspect(from p in {"users_profiles", Profile}, where: p.author_id in ^[])

    assert inspect(Ecto.Association.Has.assoc_query(assoc, nil, [1, 2, 3])) ==
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

    assert inspect(Ecto.Association.Has.assoc_query(assoc, nil, [])) ==
           inspect(from a in Author, where: a.id in ^[])

    assert inspect(Ecto.Association.Has.assoc_query(assoc, nil, [1, 2, 3])) ==
           inspect(from a in Author, where: a.id in ^[1, 2, 3])
  end

  test "belongs to with specified source" do
    assoc = Email.__schema__(:association, :author)

    assert inspect(Ecto.Association.Has.joins_query(assoc)) ==
           inspect(from e in Email, join: a in {"post_authors", Author}, on: a.id == e.author_id)

    assert inspect(Ecto.Association.Has.assoc_query(assoc, nil, [])) ==
           inspect(from a in {"post_authors", Author}, where: a.id in ^[])

    assert inspect(Ecto.Association.Has.assoc_query(assoc, nil, [1, 2, 3])) ==
           inspect(from a in {"post_authors", Author}, where: a.id in ^[1, 2, 3])
  end

  test "belongs to custom assoc query" do
    assoc = Post.__schema__(:association, :author)
    query = from a in Author, limit: 5
    assert inspect(Ecto.Association.Has.assoc_query(assoc, query, [1, 2, 3])) ==
           inspect(from a in Author, where: a.id in ^[1, 2, 3], limit: 5)
  end

  test "many to many" do
    assoc = Permalink.__schema__(:association, :authors)

    assert inspect(Ecto.Association.ManyToMany.joins_query(assoc)) ==
           inspect(from p in Permalink,
                    join: m in "authors_permalinks", on: m.permalink_id == p.id,
                    join: a in Author, on: m.author_id == a.id)

    assert inspect(Ecto.Association.ManyToMany.assoc_query(assoc, nil, [])) ==
           inspect(from a in Author,
                    join: m in "authors_permalinks", on: m.author_id == a.id,
                    where: m.permalink_id in ^[])

    assert inspect(Ecto.Association.ManyToMany.assoc_query(assoc, nil, [1, 2, 3])) ==
           inspect(from a in Author,
                    join: m in "authors_permalinks", on: m.author_id == a.id,
                    where: m.permalink_id in ^[1, 2, 3])
  end

  test "many to many with specified source" do
    assoc = Author.__schema__(:association, :permalinks)

    assert inspect(Ecto.Association.ManyToMany.joins_query(assoc)) ==
           inspect(from a in Author,
                    join: m in "authors_permalinks", on: m.author_id == a.id,
                    join: p in {"custom_permalinks", Permalink}, on: m.permalink_id == p.id)

    assert inspect(Ecto.Association.ManyToMany.assoc_query(assoc, nil, [])) ==
           inspect(from p in {"custom_permalinks", Permalink},
                    join: m in "authors_permalinks", on: m.permalink_id == p.id,
                    where: m.author_id in ^[])

    assert inspect(Ecto.Association.ManyToMany.assoc_query(assoc, nil, [1, 2, 3])) ==
           inspect(from p in {"custom_permalinks", Permalink},
                    join: m in "authors_permalinks", on: m.permalink_id == p.id,
                    where: m.author_id in ^[1, 2, 3])
  end

  test "many to many custom assoc query" do
    assoc = Permalink.__schema__(:association, :authors)
    query = from a in Author, limit: 5
    assert inspect(Ecto.Association.ManyToMany.assoc_query(assoc, query, [1, 2, 3])) ==
           inspect(from a in Author,
                    join: m in "authors_permalinks", on: m.author_id == a.id,
                    where: m.permalink_id in ^[1, 2, 3], limit: 5)
  end

  test "has many through many to many" do
    assoc = Author.__schema__(:association, :posts_comments)

    assert inspect(Ecto.Association.HasThrough.joins_query(assoc)) ==
           inspect(from a in Author, join: p in assoc(a, :posts), join: c in assoc(p, :comments))

    assert inspect(Ecto.Association.HasThrough.assoc_query(assoc, nil, [1,2,3])) ==
           inspect(from c in Comment, join: p in Post, on: p.author_id in ^[1, 2, 3],
                        where: c.post_id == p.id, distinct: true)
  end

  test "has many through many to one" do
    assoc = Author.__schema__(:association, :posts_permalinks)

    assert inspect(Ecto.Association.HasThrough.joins_query(assoc)) ==
           inspect(from a in Author, join: p in assoc(a, :posts), join: c in assoc(p, :permalink))

    assert inspect(Ecto.Association.HasThrough.assoc_query(assoc, nil, [1,2,3])) ==
           inspect(from l in Permalink, join: p in Post, on: p.author_id in ^[1, 2, 3],
                        where: l.post_id == p.id, distinct: true)
  end

  test "has one through belongs to belongs" do
    assoc = Comment.__schema__(:association, :post_author)

    assert inspect(Ecto.Association.HasThrough.joins_query(assoc)) ==
           inspect(from c in Comment, join: p in assoc(c, :post), join: a in assoc(p, :author))

    assert inspect(Ecto.Association.HasThrough.assoc_query(assoc, nil, [1,2,3])) ==
           inspect(from a in Author, join: p in Post, on: p.id in ^[1, 2, 3],
                        where: a.id == p.author_id, distinct: true)
  end

  test "has one through belongs to one" do
    assoc = Comment.__schema__(:association, :post_permalink)

    assert inspect(Ecto.Association.HasThrough.joins_query(assoc)) ==
           inspect(from c in Comment, join: p in assoc(c, :post), join: l in assoc(p, :permalink))

    assert inspect(Ecto.Association.HasThrough.assoc_query(assoc, nil, [1,2,3])) ==
           inspect(from l in Permalink, join: p in Post, on: p.id in ^[1, 2, 3],
                        where: l.post_id == p.id, distinct: true)
  end

  test "has many through one to many" do
    assoc = Summary.__schema__(:association, :post_comments)

    assert inspect(Ecto.Association.HasThrough.joins_query(assoc)) ==
           inspect(from s in Summary, join: p in assoc(s, :post), join: c in assoc(p, :comments))

    assert inspect(Ecto.Association.HasThrough.assoc_query(assoc, nil, [1,2,3])) ==
           inspect(from c in Comment, join: p in Post, on: p.summary_id in ^[1, 2, 3],
                        where: c.post_id == p.id, distinct: true)
  end

  test "has one through one to belongs" do
    assoc = Summary.__schema__(:association, :post_author)

    assert inspect(Ecto.Association.HasThrough.joins_query(assoc)) ==
           inspect(from s in Summary, join: p in assoc(s, :post), join: a in assoc(p, :author))

    assert inspect(Ecto.Association.HasThrough.assoc_query(assoc, nil, [1,2,3])) ==
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
    # has many
    assert build_assoc(%Post{id: 1}, :comments) ==
           %Comment{post_id: 1}

    # has one
    assert build_assoc(%Summary{id: 1}, :post) ==
           %Post{summary_id: 1, title: "default"}

    # belongs to
    assert build_assoc(%Post{id: 1}, :author) ==
           %Author{title: "World!"}

    # many to many
    assert build_assoc(%Permalink{id: 1}, :authors) ==
           %Author{title: "m2m!"}

    assert_raise ArgumentError, ~r"cannot build through association `:post_author`", fn ->
      build_assoc(%Comment{}, :post_author)
    end
  end

  test "build/2 with custom source" do
    email = build_assoc(%Author{id: 1}, :emails)
    assert email.__meta__.source == {nil, "users_emails"}

    profile = build_assoc(%Author{id: 1}, :profile)
    assert profile.__meta__.source == {nil, "users_profiles"}

    profile = build_assoc(%Email{id: 1}, :author)
    assert profile.__meta__.source == {nil, "post_authors"}

    permalink = build_assoc(%Author{id: 1}, :permalinks)
    assert permalink.__meta__.source == {nil, "custom_permalinks"}
  end

  test "build/3 with custom attributes" do
    # has many
    assert build_assoc(%Post{id: 1}, :comments, text: "Awesome!") ==
           %Comment{post_id: 1, text: "Awesome!"}

    assert build_assoc(%Post{id: 1}, :comments, %{text: "Awesome!"}) ==
           %Comment{post_id: 1, text: "Awesome!"}

    # has one
    assert build_assoc(%Post{id: 1}, :comments, post_id: 2) ==
           %Comment{post_id: 1}

    # belongs to
    assert build_assoc(%Post{id: 1}, :author, title: "Hello!") ==
           %Author{title: "Hello!"}

    # many to many
    assert build_assoc(%Permalink{id: 1}, :authors, title: "Hello!") ==
           %Author{title: "Hello!"}

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
    assert [{:comments, {:assoc, %Ecto.Association.Has{}, {0, :post_id}}, {nil, []}},
            {:permalink, {:assoc, %Ecto.Association.Has{}, {0, :post_id}}, {nil, []}}] =
           expand(Post, [:comments, :permalink])

    assert [{:post, {:assoc, %Ecto.Association.BelongsTo{}, {0, :id}},
            {nil, [author: {nil, []}]}}] =
           expand(Comment, [post: :author])

    assert [{:post, {:assoc, %Ecto.Association.BelongsTo{}, {0, :id}},
            {nil, [author: {nil, []}, permalink: {nil, []}]}}] =
           expand(Comment, [:post, post: :author, post: :permalink])

    assert [{:posts, {:assoc, %Ecto.Association.Has{}, {0, :author_id}}, {nil, [comments: {nil, [post: {nil, []}]}]}},
            {:posts_comments, {:through, %Ecto.Association.HasThrough{}, [:posts, :comments]}, {nil, []}}] =
           expand(Author, [posts_comments: :post])

    assert [{:posts, {:assoc, %Ecto.Association.Has{}, {0, :author_id}}, {nil, [comments: _, comments: _]}},
           {:posts_comments, {:through, %Ecto.Association.HasThrough{}, [:posts, :comments]}, {nil, []}}] =
           expand(Author, [:posts, posts_comments: :post, posts: [comments: :post]])

    query = from(c in Comment, limit: 1)
    assert [{:permalink, {:assoc, %Ecto.Association.Has{}, {0, :post_id}}, {nil, []}},
            {:comments, {:assoc, %Ecto.Association.Has{}, {0, :post_id}}, {^query, []}}] =
           expand(Post, [:permalink, comments: query])

    assert [{:posts, {:assoc, %Ecto.Association.Has{}, {0, :author_id}}, {nil, [comments: {^query, [post: {nil, []}]}]}},
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
end
