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

    def changeset(schema, params) do
      Changeset.cast(schema, params, ~w(title)a)
      |> Changeset.validate_required(:title)
    end

    def set_action(schema, params) do
      changeset(schema, params)
      |> Map.put(:action, Map.get(params, :action, :update))
    end
  end

  defmodule Author do
    use Ecto.Schema

    schema "authors" do
      field :title, :string
      many_to_many :posts, Post, join_through: "authors_posts", on_replace: :delete, defaults: [title: "default"]
      many_to_many :raise_posts, Post, join_through: "authors_posts", on_replace: :raise, defaults: {__MODULE__, :send_to_self, [:extra]}
      many_to_many :invalid_posts, Post, join_through: "authors_posts", on_replace: :mark_as_invalid
    end

    def send_to_self(struct, owner, extra) do
      send(self(), {:defaults, struct, owner, extra})
      %{struct | id: 13}
    end
  end

  defp cast(schema, params, assoc, opts \\ []) do
    schema
    |> Changeset.cast(params, ~w())
    |> Changeset.cast_assoc(assoc, opts)
  end

  test "cast many_to_many with keyword defaults" do
    changeset = cast(%Author{}, %{"posts" => [%{}]}, :posts)
    [post_change] = changeset.changes.posts
    assert post_change.data.title == "default"
    assert post_change.valid?
    assert changeset.valid?
  end

  test "cast many_to_many with MFA defaults" do
    changeset = cast(%Author{title: "Title"}, %{"raise_posts" => [%{title: "Title"}]}, :raise_posts)
    assert_received {:defaults, %Post{id: nil}, %Author{title: "Title"}, :extra}
    [post_change] = changeset.changes.raise_posts
    assert post_change.data.id == 13
    assert post_change.changes == %{title: "Title"}
    assert post_change.valid?
    assert changeset.valid?
  end

  test "cast many_to_many with only new schemas" do
    changeset = cast(%Author{}, %{"posts" => [%{"title" => "hello"}]}, :posts)
    [post_change] = changeset.changes.posts
    assert post_change.changes == %{title: "hello"}
    assert post_change.errors  == []
    assert post_change.action  == :insert
    assert post_change.valid?
    assert changeset.valid?
  end

  test "cast many_to_many with map" do
    changeset = cast(%Author{}, %{"posts" => %{0 => %{"title" => "hello"}}}, :posts)
    [post_change] = changeset.changes.posts
    assert post_change.changes == %{title: "hello"}
    assert post_change.errors  == []
    assert post_change.action  == :insert
    assert post_change.valid?
    assert changeset.valid?
  end

  test "cast many_to_many without loading" do
    assert cast(%Author{}, %{"posts" => []}, :posts).changes == %{posts: []}
    assert cast(%Author{posts: []}, %{"posts" => []}, :posts).changes == %{}

    loaded = put_in %Author{}.__meta__.state, :loaded
    assert_raise RuntimeError, ~r"attempting to cast or change association `posts` .* that was not loaded", fn ->
      cast(loaded, %{"posts" => []}, :posts)
    end
    assert cast(loaded, %{}, :posts).changes == %{}
  end

  # Please note the order is important in this test.
  test "cast many_to_many changing schemas" do
    posts = [%Post{title: "first", id: 1},
             %Post{title: "second", id: 2},
             %Post{title: "third", id: 3}]
    params = [%{"title" => "new"},
              %{"id" => 2, "title" => nil},
              %{"id" => 3, "title" => "new name"}]

    changeset = cast(%Author{posts: posts}, %{"posts" => params}, :posts)
    [first, new, second, third] = changeset.changes.posts

    assert first.data.id == 1
    assert first.required == [] # Check for not running changeset function
    assert first.action == :replace
    assert first.valid?

    assert new.changes == %{title: "new"}
    assert new.action == :insert
    assert new.valid?

    assert second.data.id == 2
    assert second.errors == [title: {"can't be blank", [validation: :required]}]
    assert second.action == :update
    refute second.valid?

    assert third.data.id == 3
    assert third.action == :update
    assert third.valid?

    refute changeset.valid?
  end

  test "cast many_to_many with invalid operation" do
    params = %{"posts" => [%{"id" => 1, "title" => "new"}]}
    assert_raise RuntimeError, ~r"cannot update related", fn ->
      cast(%Author{posts: []}, params, :posts, with: &Post.set_action/2)
    end
  end

  test "cast many_to_many with invalid params" do
    changeset = cast(%Author{}, %{"posts" => "value"}, :posts)
    assert changeset.errors == [posts: {"is invalid", [validation: :assoc, type: {:array, :map}]}]
    refute changeset.valid?

    changeset = cast(%Author{}, %{"posts" => ["value"]}, :posts)
    assert changeset.errors == [posts: {"is invalid", [validation: :assoc, type: {:array, :map}]}]
    refute changeset.valid?

    changeset = cast(%Author{}, %{"posts" => nil}, :posts)
    assert changeset.errors == [posts: {"is invalid", [validation: :assoc, type: {:array, :map}]}]
    refute changeset.valid?

    changeset = cast(%Author{}, %{"posts" => %{"id" => "invalid"}}, :posts)
    assert changeset.errors == [posts: {"is invalid", [validation: :assoc, type: {:array, :map}]}]
    refute changeset.valid?
  end

  test "cast many_to_many without changes skips" do
    changeset = cast(%Author{posts: [%Post{title: "hello", id: 1}]},
                     %{"posts" => [%{"id" => 1}]}, :posts)

    refute Map.has_key?(changeset.changes, :posts)
  end

  test "cast many_to_many discards changesets marked as ignore" do
    changeset = cast(%Author{},
                     %{"posts" => [%{title: "oops", action: :ignore}]},
                     :posts, with: &Post.set_action/2)
    assert changeset.changes == %{}

    posts = [
      %{title: "hello", action: :insert},
      %{title: "oops", action: :ignore},
      %{title: "world", action: :insert}
    ]
    changeset = cast(%Author{}, %{"posts" => posts},
                     :posts, with: &Post.set_action/2)
    assert Enum.map(changeset.changes.posts, &Ecto.Changeset.get_change(&1, :title)) ==
           ["hello", "world"]
  end

  test "cast many_to_many when required" do
    # Still no error because the loaded association is an empty list
    changeset = cast(%Author{}, %{posts: [%{title: "hello"}]}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.errors == []

    changeset = cast(%Author{posts: []}, %{}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.changes == %{}
    assert changeset.errors == [posts: {"can't be blank", [validation: :required]}]

    changeset = cast(%Author{posts: []}, %{}, :posts, required: true, required_message: "a custom message")
    assert changeset.required == [:posts]
    assert changeset.changes == %{}
    assert changeset.errors == [posts: {"a custom message", [validation: :required]}]

    changeset = cast(%Author{posts: []}, %{"posts" => nil}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.changes == %{}
    assert changeset.errors == [posts: {"is invalid", [validation: :assoc, type: {:array, :map}]}]
  end

  test "cast many_to_many with empty parameters" do
    changeset = cast(%Author{posts: []}, %{}, :posts)
    assert changeset.changes == %{}

    changeset = cast(%Author{}, %{}, :posts)
    assert changeset.changes == %{}

    changeset = cast(%Author{posts: [%Post{}]}, %{}, :posts)
    assert changeset.changes == %{}
  end

  test "cast many_to_many with on_replace: :raise" do
    schema = %Author{raise_posts: [%Post{id: 1}]}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(schema, %{"raise_posts" => []}, :raise_posts)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(schema, %{"raise_posts" => [%{"id" => 2}]}, :raise_posts)
    end
  end

  test "cast many_to_many with on_replace: :mark_as_invalid" do
    schema = %Author{invalid_posts: [%Post{id: 1}]}

    changeset = cast(schema, %{"invalid_posts" => []}, :invalid_posts)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"is invalid", [validation: :assoc, type: {:array, :map}]}]
    refute changeset.valid?

    changeset = cast(schema, %{"invalid_posts" => [%{"id" => 2}]}, :invalid_posts)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"is invalid", [validation: :assoc, type: {:array, :map}]}]
    refute changeset.valid?

    changeset = cast(schema, %{"invalid_posts" => [%{"id" => 2}]}, :invalid_posts, invalid_message: "a custom message")
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"a custom message", [validation: :assoc, type: {:array, :map}]}]
    refute changeset.valid?
  end

  test "cast many_to_many twice" do
    schema = %Author{}

    params = %{posts: [%{title: "hello", id: 1}]}
    schema = cast(schema, params, :posts) |> Changeset.apply_changes
    params = %{posts: []}
    changeset = cast(schema, params, :posts)
    changeset = cast(changeset, params, :posts)
    assert changeset.valid?

    schema = %Author{}
    params = %{posts: [%{title: "hello"}]}
    changeset = cast(schema, params, :posts)
    changeset = cast(changeset, params, :posts)
    assert changeset.valid?
  end

  test "change many_to_many" do
    assoc = Author.__schema__(:association, :posts)

    assert {:ok, [], true} = Relation.change(assoc, [], [])

    assert {:ok, [old_changeset, new_changeset], true} =
      Relation.change(assoc, [%Post{id: 1}], [%Post{id: 2}])
    assert old_changeset.action == :replace
    assert new_changeset.action == :insert

    assoc_schema_changeset = Changeset.change(%Post{}, title: "hello")

    assert {:ok, [changeset], true} =
      Relation.change(assoc, [assoc_schema_changeset], [])
    assert changeset.action == :insert
    assert changeset.changes == %{title: "hello"}

    assoc_schema = %Post{id: 1}
    assoc_schema_changeset = Changeset.change(assoc_schema, title: "hello")
    assert {:ok, [changeset], true} =
      Relation.change(assoc, [assoc_schema_changeset], [assoc_schema])
    assert changeset.action == :update
    assert changeset.changes == %{title: "hello"}

    assert {:ok, [changeset], true} =
      Relation.change(assoc, [], [assoc_schema_changeset])
    assert changeset.action == :replace

    assert :ignore =
      Relation.change(assoc, [%{assoc_schema_changeset | action: :ignore}], [assoc_schema])
    assert :ignore =
      Relation.change(assoc, [%{assoc_schema_changeset | action: :ignore}], [])

    empty_changeset = Changeset.change(assoc_schema)
    assert :ignore =
      Relation.change(assoc, [empty_changeset], [assoc_schema])
  end

  test "change many_to_many with attributes" do
    assoc = Author.__schema__(:association, :posts)

    assert {:ok, [changeset], true} =
      Relation.change(assoc, [%{title: "hello"}], [])
    assert changeset.action == :insert
    assert changeset.changes == %{title: "hello"}

    post = %Post{title: "other"} |> Ecto.put_meta(state: :loaded)

    assert {:ok, [changeset], true} =
      Relation.change(assoc, [%{title: "hello"}], [post])
    assert changeset.action == :update
    assert changeset.changes == %{title: "hello"}

    assert {:ok, [changeset], true} =
      Relation.change(assoc, [[title: "hello"]], [post])
    assert changeset.action == :update
    assert changeset.changes == %{title: "hello"}
  end

  test "change many_to_many with structs" do
    assoc = Author.__schema__(:association, :posts)
    post = %Post{title: "hello"}

    assert {:ok, [changeset], true} =
      Relation.change(assoc, [post], [])
    assert changeset.action == :insert

    assert {:ok, [changeset], true} =
      Relation.change(assoc, [Ecto.put_meta(post, state: :loaded)], [])
    assert changeset.action == :update

    assert {:ok, [changeset], true} =
      Relation.change(assoc, [Ecto.put_meta(post, state: :deleted)], [])
    assert changeset.action == :delete
  end

  test "change many_to_many with on_replace: :raise" do
    assoc_schema = %Post{id: 1}
    base_changeset = Changeset.change(%Author{raise_posts: [assoc_schema]})

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :raise_posts, [])
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :raise_posts, [%Post{id: 2}])
    end
  end

  test "change many_to_many with on_replace: :mark_as_invalid" do
    assoc_schema = %Post{id: 1}
    base_changeset = Changeset.change(%Author{invalid_posts: [assoc_schema]})

    changeset = Changeset.put_assoc(base_changeset, :invalid_posts, [])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"is invalid", [type: {:array, :map}]}]
    refute changeset.valid?

    changeset = Changeset.put_assoc(base_changeset, :invalid_posts, [%Post{id: 2}])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"is invalid", [type: {:array, :map}]}]
    refute changeset.valid?

    changeset = Changeset.put_assoc(base_changeset, :invalid_posts, [])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"is invalid", [type: {:array, :map}]}]
    refute changeset.valid?

    changeset = Changeset.put_assoc(base_changeset, :invalid_posts, [%Post{id: 2}])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"is invalid", [type: {:array, :map}]}]
    refute changeset.valid?
  end

  test "apply_changes" do
    changeset1 = Changeset.change(%Post{}, title: "hello")
    changeset2 = %{changeset1 | action: :delete}

    assoc = Author.__schema__(:association, :posts)
    [schema] = Relation.apply_changes(assoc, [changeset1, changeset2])
    assert schema == %Post{title: "hello"}
  end
end
