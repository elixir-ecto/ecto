defmodule Ecto.EmbeddedTest do
  use ExUnit.Case, async: true
  doctest Ecto.Embedded

  alias Ecto.Changeset
  alias Ecto.Changeset.Relation
  alias Ecto.Embedded

  alias __MODULE__.Author
  alias __MODULE__.Profile
  alias __MODULE__.Post

  defmodule Author do
    use Ecto.Model

    schema "authors" do
      embeds_one :profile, Profile, on_cast: :required_changeset, on_replace: :delete
      embeds_many :posts, Post, on_replace: :delete
      embeds_one :raise_profile, Profile
      embeds_many :raise_posts, Post
      embeds_one :invalid_profile, Profile, on_replace: :mark_as_invalid
      embeds_many :invalid_posts, Post, on_replace: :mark_as_invalid
    end
  end

  defmodule Post do
    use Ecto.Model

    schema "posts" do
      field :title, :string
    end

    def changeset(model, params) do
      cast(model, params, ~w(title))
    end

    def optional_changeset(model, params) do
      cast(model, params, ~w(), ~w(title))
    end

    def set_action(model, params) do
      cast(model, params, ~w(title))
      |> Map.put(:action, :update)
    end
  end

  defmodule Profile do
    use Ecto.Model

    embedded_schema do
      field :name
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

  test "__schema__" do
    assert Author.__schema__(:embeds) ==
      [:profile, :posts, :raise_profile, :raise_posts, :invalid_profile, :invalid_posts]

    assert Author.__schema__(:embed, :profile) ==
      %Embedded{field: :profile, cardinality: :one, owner: Author, on_replace: :delete,
                related: Profile, strategy: :replace, on_cast: :required_changeset}

    assert Author.__schema__(:embed, :posts) ==
      %Embedded{field: :posts, cardinality: :many, owner: Author, on_replace: :delete,
                related: Post, strategy: :replace, on_cast: :changeset}
  end

  ## Cast embeds one

  test "cast embeds_one with valid params" do
    changeset = Changeset.cast(%Author{}, %{"profile" => %{"name" => "michal"}}, ~w(profile))
    profile = changeset.changes.profile
    assert changeset.required == [:profile]
    assert profile.changes == %{name: "michal"}
    assert profile.errors == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast embeds_one with invalid params" do
    changeset = Changeset.cast(%Author{}, %{"profile" => %{}}, ~w(profile))
    assert changeset.changes.profile.changes == %{}
    assert changeset.changes.profile.errors  == [name: "can't be blank"]
    assert changeset.changes.profile.action  == :insert
    refute changeset.changes.profile.valid?
    refute changeset.valid?

    changeset = Changeset.cast(%Author{}, %{"profile" => "value"}, ~w(profile))
    assert changeset.errors == [profile: "is invalid"]
    refute changeset.valid?
  end

  test "cast embeds_one with existing model updating" do
    changeset =
      Changeset.cast(%Author{profile: %Profile{name: "michal", id: "michal"}},
                     %{"profile" => %{"name" => "new", "id" => "michal"}}, ~w(profile))

    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.action  == :update
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast embeds_one with existing model replacing" do
    changeset =
      Changeset.cast(%Author{profile: %Profile{name: "michal", id: "michal"}},
                     %{"profile" => %{"name" => "new"}}, ~w(profile))

    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?

    changeset =
      Changeset.cast(%Author{profile: %Profile{name: "michal", id: "michal"}},
                     %{"profile" => %{"name" => "new", "id" => "new"}}, ~w(profile))
    profile = changeset.changes.profile
    assert profile.changes == %{name: "new", id: "new"}
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

  test "cast embeds_one without changes skips" do
    changeset =
      Changeset.cast(%Author{profile: %Profile{name: "michal", id: "michal"}},
                     %{"profile" => %{"id" => "michal"}}, ~w(profile))
    assert changeset.changes == %{}
    assert changeset.errors == []
  end

  test "cast embeds_one when required" do
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

  test "cast embeds_one with custom changeset" do
    changeset = Changeset.cast(%Author{}, %{"profile" => %{"name" => "michal"}},
                     [profile: :optional_changeset])
    profile = changeset.changes.profile
    assert changeset.required == [:profile]
    assert profile.changes == %{name: "michal"}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?

    changeset = Changeset.cast(%Author{}, %{"profile" => %{}}, [profile: :optional_changeset])
    profile = changeset.changes.profile
    assert changeset.required == [:profile]
    assert profile.changes == %{}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast embeds_one keeps appropriate action from changeset" do
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

  test "cast embeds_one with :empty parameters" do
    changeset = Changeset.cast(%Author{profile: nil}, :empty, profile: :optional_changeset)
    assert changeset.changes == %{}

    changeset = Changeset.cast(%Author{profile: %Profile{}}, :empty, profile: :optional_changeset)
    assert changeset.changes == %{}
  end

  test "cast embeds_one with on_replace: :raise" do
    model = %Author{raise_profile: %Profile{}}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.cast(model, %{"raise_profile" => nil}, [], [:raise_profile])
    end

    model = %Author{raise_profile: %Profile{id: 1}}
    params = %{"raise_profile" => %{"name" => "new", "id" => 2}}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.cast(model, params, [:raise_profile])
    end
  end

  test "cast has_one with on_replace: :mark_as_invalid" do
    model = %Author{invalid_profile: %Profile{id: 1}}

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

  ## cast embeds many

  test "cast embeds_many with only new models" do
    changeset = Changeset.cast(%Author{}, %{"posts" => [%{"title" => "hello"}]}, ~w(posts))
    [post_change] = changeset.changes.posts
    assert post_change.changes == %{title: "hello"}
    assert post_change.errors  == []
    assert post_change.action  == :insert
    assert post_change.valid?
    assert changeset.valid?
  end

  test "cast embeds_many with map" do
    changeset = Changeset.cast(%Author{}, %{"posts" => %{0 => %{"title" => "hello"}}}, ~w(posts))
    [post_change] = changeset.changes.posts
    assert post_change.changes == %{title: "hello"}
    assert post_change.errors  == []
    assert post_change.action  == :insert
    assert post_change.valid?
    assert changeset.valid?
  end

  test "cast embeds_many with custom changeset" do
    changeset = Changeset.cast(%Author{}, %{"posts" => [%{"title" => "hello"}]},
                               [posts: :optional_changeset])
    [post_change] = changeset.changes.posts
    assert post_change.changes == %{title: "hello"}
    assert post_change.errors  == []
    assert post_change.action  == :insert
    assert post_change.valid?
    assert changeset.valid?
  end

  # Please note the order is important in this test.
  test "cast embeds_many changing models" do
    posts = [%Post{title: "hello",   id: 1},
             %Post{title: "unknown", id: 2},
             %Post{title: "other",   id: 3}]
    params = [%{"title" => "new"},
              %{"id" => "2", "title" => nil},
              %{"id" => "3", "title" => "new name"}]

    changeset = Changeset.cast(%Author{posts: posts}, %{"posts" => params}, ~w(posts))
    [hello, new, unknown, other] = changeset.changes.posts
    assert hello.model.id == 1
    assert hello.required == [] # Check for not running chgangeset function
    assert hello.action == :delete
    assert hello.valid?
    assert new.changes == %{title: "new"}
    assert new.action == :insert
    assert new.valid?
    assert unknown.model.id == 2
    assert unknown.errors == [title: "can't be blank"]
    assert unknown.action == :update
    refute unknown.valid?
    assert other.model.id == 3
    assert other.action == :update
    assert other.valid?
    refute changeset.valid?

    params = %{"posts" => [%{"id" => "10", "title" => "post"}]}
    changeset = Changeset.cast(%Author{posts: []}, params, ~w(posts))
    [post] = changeset.changes.posts
    assert post.changes == %{title: "post"}
    assert post.action  == :insert

    assert_raise RuntimeError, ~r"cannot update .* it does not exist in the parent model", fn ->
      Changeset.cast(%Author{posts: []}, params, [posts: :set_action])
    end
  end

  test "cast embeds_many with invalid params" do
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

  test "cast embeds_many without changes skips" do
    changeset =
      Changeset.cast(%Author{posts: [%Post{title: "hello", id: 1}]},
                     %{"posts" => [%{"id" => 1}]}, ~w(posts))

    refute Map.has_key?(changeset.changes, :posts)
  end

  test "cast embeds_many when required" do
    changeset =
      Changeset.cast(%Author{posts: []}, %{}, ~w(posts))
    assert changeset.changes == %{}
    assert changeset.errors == []

    changeset =
      Changeset.cast(%Author{posts: []}, %{"posts" => nil}, ~w(posts))
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "is invalid"]
  end

  test "cast embeds_many with :empty parameters" do
    changeset = Changeset.cast(%Author{posts: []}, :empty, ~w(posts))
    assert changeset.changes == %{}

    changeset = Changeset.cast(%Author{posts: [%Post{}]}, :empty, ~w(posts))
    assert changeset.changes == %{}
  end

  test "cast embeds_many with on_replace: :raise" do
    model = %Author{raise_posts: [%Post{id: 1}]}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.cast(model, %{"raise_posts" => []}, [:raise_posts])
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.cast(model, %{"raise_posts" => [%{"id" => 2}]}, [:raise_posts])
    end
  end

  test "cast has_many with on_replace: :mark_as_invalid" do
    model = %Author{invalid_posts: [%Post{id: 1}]}

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

  ## Others

  test "change embeds_one" do
    model = %Author{}
    embed = Author.__schema__(:embed, :profile)

    assert {:ok, changeset, true, false} =
      Relation.change(embed, model, %Profile{name: "michal"}, nil)
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, name: "michal"}

    assert {:ok, changeset, true, false} =
      Relation.change(embed, model, %Profile{name: "michal"}, %Profile{})
    assert changeset.action == :update
    assert changeset.changes == %{name: "michal"}

    assert {:ok, changeset, true, false} =
      Relation.change(embed, model, nil, %Profile{})
    assert changeset.action == :delete

    embed_model = %Profile{}
    embed_model_changeset = Changeset.change(embed_model, name: "michal")

    assert {:ok, changeset, true, false} =
      Relation.change(embed, model, embed_model_changeset, nil)
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, name: "michal"}

    assert {:ok, changeset, true, false} =
      Relation.change(embed, model, embed_model_changeset, embed_model)
    assert changeset.action == :update
    assert changeset.changes == %{name: "michal"}

    empty_changeset = Changeset.change(embed_model)
    assert {:ok, _, true, true} =
      Relation.change(embed, model, empty_changeset, embed_model)

    embed_with_id = %Profile{id: 2}
    assert {:ok, _, true, false} =
      Relation.change(embed, model, %Profile{id: 1}, embed_with_id)

    update_changeset = %{Changeset.change(embed_model) | action: :delete}
    assert_raise RuntimeError, ~r"cannot delete .* it does not exist in the parent model", fn ->
      Relation.change(embed, model, update_changeset, embed_with_id)
    end
  end

  test "change embeds_one keeps appropriate action from changeset" do
    model = %Author{}
    embed = Author.__schema__(:embed, :profile)
    embed_model = %Profile{}

    changeset = %{Changeset.change(embed_model, name: "michal") | action: :insert}

    {:ok, changeset, _, _} = Relation.change(embed, model, changeset, nil)
    assert changeset.action == :insert

    changeset = %{changeset | action: :delete}
    assert_raise RuntimeError, ~r"cannot delete .* it does not exist in the parent model", fn ->
      Relation.change(embed, model, changeset, nil)
    end

    changeset = %{Changeset.change(embed_model) | action: :update}
    {:ok, changeset, _, _} = Relation.change(embed, model, changeset, embed_model)
    assert changeset.action == :update

    embed_model = %{embed_model | id: 5}
    model = %{model | profile: embed_model}
    changeset = %{Changeset.change(embed_model) | action: :insert}
    assert_raise RuntimeError, ~r"cannot insert .* it already exists in the parent model", fn ->
      Relation.change(embed, model, changeset, embed_model)
    end
  end

  test "change embeds_one with on_replace: :raise" do
    model = %Author{}
    embed = Author.__schema__(:embed, :raise_profile)
    embed_model = %Author{id: 1}

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Relation.change(embed, model, nil, embed_model)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Relation.change(embed, model, %Author{id: 2}, embed_model)
    end
  end

  test "change embeds_many" do
    model = %Author{}
    embed = Author.__schema__(:embed, :posts)

    assert {:ok, [changeset], true, false} =
      Relation.change(embed, model, [%Post{title: "hello"}], [])
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, title: "hello"}

    assert {:ok, [changeset], true, false} =
      Relation.change(embed, model, [%Post{id: 1, title: "hello"}], [%Post{id: 1}])
    assert changeset.action == :update
    assert changeset.changes == %{title: "hello"}

    assert {:ok, [old_changeset, new_changeset], true, false} =
      Relation.change(embed, model, [%Post{id: 1}], [%Post{id: 2}])
    assert old_changeset.action  == :delete
    assert new_changeset.action  == :insert
    assert new_changeset.changes == %{id: 1, title: nil}

    embed_model_changeset = Changeset.change(%Post{}, title: "hello")

    assert {:ok, [changeset], true, false} =
      Relation.change(embed, model, [embed_model_changeset], [])
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, title: "hello"}

    embed_model = %Post{id: 1}
    embed_model_changeset = Changeset.change(embed_model, title: "hello")
    assert {:ok, [changeset], true, false} =
      Relation.change(embed, model, [embed_model_changeset], [embed_model])
    assert changeset.action == :update
    assert changeset.changes == %{title: "hello"}

    assert {:ok, [changeset], true, false} =
      Relation.change(embed, model, [], [embed_model_changeset])
    assert changeset.action == :delete

    empty_changeset = Changeset.change(embed_model)
    assert {:ok, _, true, true} =
      Relation.change(embed, model, [empty_changeset], [embed_model])

    new_model_update = %{Changeset.change(%Post{id: 2}) | action: :update}
    assert_raise RuntimeError, ~r"cannot update .* it does not exist in the parent model", fn ->
      Relation.change(embed, model, [new_model_update], [embed_model])
    end
  end

  test "change has_many with on_replace: :raise" do
    model = %Author{}
    embed = Author.__schema__(:embed, :raise_posts)
    embed_model = %Post{id: 1}

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Relation.change(embed, model, [], [embed_model])
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Relation.change(embed, model, [%Post{id: 2}], [embed_model])
    end
  end

  test "change/2, put_change/3, force_change/3 wth embeds" do
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

  test "get_field/3, fetch_field/2 with embeds" do
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

  test "empty" do
    assert Relation.empty(%Embedded{cardinality: :one}) == nil
    assert Relation.empty(%Embedded{cardinality: :many}) == []
  end

  test "apply_changes" do
    embed = Author.__schema__(:embed, :profile)

    changeset = Changeset.change(%Profile{}, name: "michal")
    model = Relation.apply_changes(embed, changeset)
    assert model == %Profile{name: "michal"}

    changeset = Changeset.change(%Post{}, title: "hello")
    changeset2 = %{changeset | action: :delete}
    assert Relation.apply_changes(embed, changeset2) == nil

    embed = Author.__schema__(:embed, :posts)
    [model] = Relation.apply_changes(embed, [changeset, changeset2])
    assert model == %Post{title: "hello"}
  end
end
