defmodule Ecto.Changeset.ManyToManyTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Ecto.Changeset.Relation

  alias __MODULE__.Author
  alias __MODULE__.Post

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field :title, :string
    end

    def changeset(model, params) do
      Changeset.cast(model, params, ~w(title), ~w())
    end

    def set_action(model, params) do
      Changeset.cast(model, params, ~w(title), [])
      |> Map.put(:action, :update)
    end
  end

  defmodule Author do
    use Ecto.Schema

    schema "authors" do
      field :title, :string
      many_to_many :posts, Post, join_through: "authors_posts", on_replace: :delete
      many_to_many :raise_posts, Post, join_through: "authors_posts", on_replace: :raise
      many_to_many :invalid_posts, Post, join_through: "authors_posts", on_replace: :mark_as_invalid
    end
  end

  defp cast(model, params, assoc, opts \\ []) do
    model
    |> Changeset.cast(params, ~w(), ~w())
    |> Changeset.cast_assoc(assoc, opts)
  end

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
    assert first.action == :replace
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
    assert_raise RuntimeError, ~r"cannot update related", fn ->
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
    changeset = cast(%Author{}, %{posts: [%{title: "hello"}]}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.errors == []

    changeset = cast(%Author{posts: []}, %{}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "can't be blank"]

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
    model = %Author{raise_posts: [%Post{id: 1}]}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(model, %{"raise_posts" => []}, :raise_posts)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(model, %{"raise_posts" => [%{"id" => 2}]}, :raise_posts)
    end
  end

  test "cast has_many with on_replace: :mark_as_invalid" do
    model = %Author{invalid_posts: [%Post{id: 1}]}

    changeset = cast(model, %{"invalid_posts" => []}, :invalid_posts)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: "is invalid"]
    refute changeset.valid?

    changeset = cast(model, %{"invalid_posts" => [%{"id" => 2}]}, :invalid_posts)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: "is invalid"]
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

  test "change has_many" do
    assoc = Author.__schema__(:association, :posts)

    assert {:ok, [old_changeset, new_changeset], true, false} =
      Relation.change(assoc, [%Post{id: 1}], [%Post{id: 2}])
    assert old_changeset.action == :replace
    assert new_changeset.action == :insert

    assoc_model_changeset = Changeset.change(%Post{}, title: "hello")

    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, [assoc_model_changeset], [])
    assert changeset.action == :insert
    assert changeset.changes == %{title: "hello"}

    assoc_model = %Post{id: 1}
    assoc_model_changeset = Changeset.change(assoc_model, title: "hello")
    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, [assoc_model_changeset], [assoc_model])
    assert changeset.action == :update
    assert changeset.changes == %{title: "hello"}

    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, [], [assoc_model_changeset])
    assert changeset.action == :replace

    empty_changeset = Changeset.change(assoc_model)
    assert {:ok, _, true, true} =
      Relation.change(assoc, [empty_changeset], [assoc_model])
  end

  test "change has_many with structs" do
    assoc = Author.__schema__(:association, :posts)
    post = %Post{title: "hello"}

    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, [post], [])
    assert changeset.action == :insert

    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, [Ecto.put_meta(post, state: :loaded)], [])
    assert changeset.action == :update

    assert {:ok, [changeset], true, false} =
      Relation.change(assoc, [Ecto.put_meta(post, state: :deleted)], [])
    assert changeset.action == :delete
  end

  test "change has_many with on_replace: :raise" do
    assoc_model = %Post{id: 1}
    base_changeset = Changeset.change(%Author{raise_posts: [assoc_model]})

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :raise_posts, [])
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :raise_posts, [%Post{id: 2}])
    end
  end

  test "change has_many with on_replace: :mark_as_invalid" do
    assoc_model = %Post{id: 1}
    base_changeset = Changeset.change(%Author{invalid_posts: [assoc_model]})

    changeset = Changeset.put_assoc(base_changeset, :invalid_posts, [])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.put_assoc(base_changeset, :invalid_posts, [%Post{id: 2}])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.put_assoc(base_changeset, :invalid_posts, [])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.put_assoc(base_changeset, :invalid_posts, [%Post{id: 2}])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: "is invalid"]
    refute changeset.valid?
  end

  test "apply_changes" do
    changeset1 = Changeset.change(%Post{}, title: "hello")
    changeset2 = %{changeset1 | action: :delete}

    assoc = Author.__schema__(:association, :posts)
    [model] = Relation.apply_changes(assoc, [changeset1, changeset2])
    assert model == %Post{title: "hello"}
  end
end
