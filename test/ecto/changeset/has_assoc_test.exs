defmodule Ecto.Changeset.HasAssocTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Ecto.Changeset.Relation

  alias __MODULE__.Author
  alias __MODULE__.Post
  alias __MODULE__.Profile

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field :title, :string
      belongs_to :author, Author
    end

    def changeset(model, params) do
      Changeset.cast(model, params, ~w(title), ~w(author_id))
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
      has_many :posts, Post, on_replace: :delete
      has_many :raise_posts, Post, on_replace: :raise
      has_many :nilify_posts, Post, on_replace: :nilify
      has_many :invalid_posts, Post, on_replace: :mark_as_invalid
      has_one :profile, {"users_profiles", Profile},
        defaults: [name: "default"], on_replace: :delete
      has_one :raise_profile, Profile, on_replace: :raise
      has_one :nilify_profile, Profile, on_replace: :nilify
      has_one :invalid_profile, Profile, on_replace: :mark_as_invalid
    end
  end

  defmodule Profile do
    use Ecto.Schema

    schema "profiles" do
      field :name
      belongs_to :author, Author
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

    assert_raise RuntimeError, ~r"cannot update related", fn ->
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
    assert changeset.changes.profile == nil
    assert changeset.valid?
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

    assert_raise RuntimeError, ~r"cannot update related", fn ->
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
    model = %Author{raise_profile: %Profile{id: 1}}

    params = %{"raise_profile" => %{"name" => "jose", "id" => "1"}}
    changeset = cast(model, params, :raise_profile)
    assert changeset.changes.raise_profile.action == :update

    params = %{"raise_profile" => nil}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(model, params, :raise_profile)
    end

    params = %{"raise_profile" => %{"name" => "new", "id" => 2}}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(model, params, :raise_profile)
    end
  end

  test "cast has_one with on_replace: :mark_as_invalid" do
    model = %Author{invalid_profile: %Profile{id: 1}}

    changeset = cast(model, %{"invalid_profile" => nil}, :invalid_profile)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: "is invalid"]
    refute changeset.valid?

    changeset = cast(model, %{"invalid_profile" => %{"id" => 2}}, :invalid_profile)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: "is invalid"]
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

  ## Change

  test "change has_one" do
    assoc = Author.__schema__(:association, :profile)

    assert {:ok, nil, true, false} =
      Relation.change(assoc, nil, %Profile{})
    assert {:ok, nil, true, true} =
      Relation.change(assoc, nil, nil)

    assoc_model = %Profile{}
    assoc_model_changeset = Changeset.change(assoc_model, name: "michal")

    assert {:ok, changeset, true, false} =
      Relation.change(assoc, assoc_model_changeset, nil)
    assert changeset.action == :insert
    assert changeset.changes == %{name: "michal"}

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
  end

  test "change has_one with structs" do
    assoc = Author.__schema__(:association, :profile)
    profile = %Profile{name: "michal"}

    assert {:ok, changeset, true, false} =
      Relation.change(assoc, profile, nil)
    assert changeset.action == :insert

    assert {:ok, changeset, true, false} =
      Relation.change(assoc, Ecto.put_meta(profile, state: :loaded), nil)
    assert changeset.action == :update

    assert {:ok, changeset, true, false} =
      Relation.change(assoc, Ecto.put_meta(profile, state: :deleted), nil)
    assert changeset.action == :delete
  end

  test "change has_one with on_replace: :nilify" do
    # one case is handled inside repo
    profile = %Profile{id: 1, author_id: 5}
    changeset = cast(%Author{nilify_profile: profile}, %{"nilify_profile" => nil}, :nilify_profile)
    assert changeset.changes.nilify_profile == nil
  end

  test "change has_one keeps appropriate action from changeset" do
    assoc = Author.__schema__(:association, :profile)
    assoc_model = %Profile{}

    # Adding
    changeset = %{Changeset.change(assoc_model, name: "michal") | action: :insert}
    {:ok, changeset, _, _} = Relation.change(assoc, changeset, nil)
    assert changeset.action == :insert

    changeset = %{Changeset.change(assoc_model) | action: :update}
    {:ok, changeset, _, _} = Relation.change(assoc, changeset, nil)
    assert changeset.action == :update

    changeset = %{Changeset.change(assoc_model) | action: :delete}
    {:ok, changeset, _, _} = Relation.change(assoc, changeset, nil)
    assert changeset.action == :delete

    # Replacing
    changeset = %{Changeset.change(assoc_model, name: "michal") | action: :insert}
    assert_raise RuntimeError, ~r/cannot insert related/, fn ->
      Relation.change(assoc, changeset, assoc_model)
    end

    changeset = %{Changeset.change(assoc_model) | action: :update}
    {:ok, changeset, _, _} = Relation.change(assoc, changeset, nil)
    assert changeset.action == :update

    changeset = %{Changeset.change(assoc_model) | action: :delete}
    {:ok, changeset, _, _} = Relation.change(assoc, changeset, nil)
    assert changeset.action == :delete
  end

  test "change has_one with on_replace: :raise" do
    assoc_model = %Profile{id: 1}
    base_changeset = Changeset.change(%Author{raise_profile: assoc_model})

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :raise_profile, nil)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :raise_profile, %Profile{id: 2})
    end
  end

  test "change has_one with on_replace: :mark_as_invalid" do
    assoc_model = %Profile{id: 1}
    base_changeset = Changeset.change(%Author{invalid_profile: assoc_model})

    changeset = Changeset.put_assoc(base_changeset, :invalid_profile, nil)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.put_assoc(base_changeset, :invalid_profile, %Profile{id: 2})
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: "is invalid"]
    refute changeset.valid?
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

  test "change has_many with on_replace: :nilify" do
    post = %Post{id: 1, author_id: 5}
    changeset = cast(%Author{nilify_posts: [post]}, %{"nilify_posts" => []}, :nilify_posts)
    [post_change] = changeset.changes.nilify_posts
    assert post_change.action == :replace
    assert post_change.changes == %{}
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

  test "apply_changes" do
    assoc = Author.__schema__(:association, :profile)

    changeset = Changeset.change(%Profile{}, name: "michal")
    model = Relation.apply_changes(assoc, changeset)
    assert model == %Profile{name: "michal"}

    changeset1 = Changeset.change(%Post{}, title: "hello")
    changeset2 = %{changeset1 | action: :delete}
    assert Relation.apply_changes(assoc, changeset2) == nil

    assoc = Author.__schema__(:association, :posts)
    [model] = Relation.apply_changes(assoc, [changeset1, changeset2])
    assert model == %Post{title: "hello"}
  end
end
