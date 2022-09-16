defmodule Ecto.Changeset.HasAssocTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Ecto.Changeset.Relation
  alias Ecto.TestRepo

  alias __MODULE__.Author
  alias __MODULE__.Post
  alias __MODULE__.Profile

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field :title, :string
      belongs_to :author, Author
    end

    def changeset(schema, params) do
      Changeset.cast(schema, params, ~w(title author_id)a)
      |> Changeset.validate_required(:title)
      |> Changeset.validate_length(:title, min: 3)
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
      has_many :posts, Post, on_replace: :delete,
        defaults: [title: "default"]
      has_many :raise_posts, Post, on_replace: :raise
      has_many :nilify_posts, Post, on_replace: :nilify,
        defaults: {__MODULE__, :send_to_self, [:extra]}
      has_many :invalid_posts, Post, on_replace: :mark_as_invalid
      has_one :profile, {"users_profiles", Profile},
        defaults: [name: "default"], on_replace: :delete
      has_one :raise_profile, Profile, on_replace: :raise
      has_one :nilify_profile, Profile, on_replace: :nilify
      has_one :invalid_profile, Profile, on_replace: :mark_as_invalid,
        defaults: :send_to_self
      has_one :update_profile, Profile, on_replace: :update,
        defaults: {__MODULE__, :send_to_self, [:extra]}
    end

    def send_to_self(struct, owner, extra \\ :default) do
      send(self(), {:defaults, struct, owner, extra})
      %{struct | id: 13}
    end
  end

  defmodule Profile do
    use Ecto.Schema

    schema "profiles" do
      field :name
      belongs_to :author, Author
    end

    def changeset(schema, params) do
      Changeset.cast(schema, params, ~w(name id)a)
      |> Changeset.validate_required(:name)
      |> Changeset.validate_length(:name, min: 3)
    end

    def optional_changeset(schema, params) do
      Changeset.cast(schema, params, ~w(name)a)
    end
    
    def failing_changeset(schema, params, error_string) do
      Changeset.cast(schema, params, ~w(name)a)
      |> Changeset.add_error(:name, error_string)
    end

    def set_action(schema, params) do
      changeset(schema, params)
      |> Map.put(:action, Map.get(params, :action, :update))
    end
  end

  defp cast(schema, params, assoc, opts \\ []) do
    schema
    |> Changeset.cast(params, ~w())
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
    assert changeset.changes.profile.errors  == [name: {"can't be blank", [validation: :required]}]
    assert changeset.changes.profile.action  == :insert
    refute changeset.changes.profile.valid?
    refute changeset.valid?

    changeset = cast(%Author{}, %{"profile" => "value"}, :profile)
    assert changeset.errors == [profile: {"is invalid", [validation: :assoc, type: :map]}]
    refute changeset.valid?
  end

  test "cast has_one with existing struct updating" do
    changeset = cast(%Author{profile: %Profile{name: "michal", id: 1}},
                     %{"profile" => %{"name" => "new", "id" => 1}}, :profile)

    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.action  == :update
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast has_one with empty value" do
    assert cast(%Author{}, %{"profile" => nil}, :profile).changes == %{profile: nil}
    assert cast(%Author{profile: nil}, %{"profile" => nil}, :profile).changes == %{}

    assert cast(%Author{}, %{"profile" => ""}, :profile).changes == %{}
    assert cast(%Author{profile: nil}, %{"profile" => ""}, :profile).changes == %{}

    loaded = put_in %Author{}.__meta__.state, :loaded
    assert_raise RuntimeError, ~r"attempting to cast or change association `profile` .* that was not loaded", fn ->
      cast(loaded, %{"profile" => nil}, :profile)
    end
    assert_raise RuntimeError, ~r"attempting to cast or change association `profile` .* that was not loaded", fn ->
      cast(loaded, %{"profile" => ""}, :profile)
    end
    assert cast(loaded, %{}, :profile).changes == %{}
  end

  test "cast has_one with existing struct replacing" do
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

  test "cast has_one with existing struct updating from atom params" do
    # Emulate atom params from nested associations
    changeset = Changeset.cast(%Author{profile: %Profile{name: "michal", id: 3}}, %{}, ~w())
    changeset = put_in changeset.params, %{"profile" => %{name: "new", id: 3}}

    changeset = Changeset.cast_assoc(changeset, :profile, [])
    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.action  == :update
    assert profile.valid?
    assert changeset.valid?
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
    assert changeset.errors == [profile: {"can't be blank", [validation: :required]}]

    changeset = cast(%Author{}, %{}, :profile, required: true, required_message: "a custom message")
    assert changeset.required == [:profile]
    assert changeset.changes == %{}
    assert changeset.errors == [profile: {"a custom message", [validation: :required]}]

    changeset = cast(%Author{profile: nil}, %{}, :profile, required: true)
    assert changeset.required == [:profile]
    assert changeset.changes == %{}
    assert changeset.errors == [profile: {"can't be blank", [validation: :required]}]

    changeset = cast(%Author{profile: %Profile{}}, %{}, :profile, required: true)
    assert changeset.required == [:profile]
    assert changeset.changes == %{}
    assert changeset.errors == []

    changeset = cast(%Author{profile: nil}, %{"profile" => nil}, :profile, required: true)
    assert changeset.required == [:profile]
    assert changeset.changes == %{}
    assert changeset.errors == [profile: {"can't be blank", [validation: :required]}]

    changeset = cast(%Author{profile: %Profile{}}, %{"profile" => nil}, :profile, required: true)
    assert changeset.required == [:profile]
    assert changeset.changes == %{profile: nil}
    assert changeset.errors == [profile: {"can't be blank", [validation: :required]}]
  end

  test "cast has_one with `:force_update_on_change` option" do
    changeset = cast(%Author{}, %{profile: %{name: "michal"}}, :profile,
                     force_update_on_change: true)
    assert changeset.repo_opts[:force]

    changeset = cast(%Author{}, %{profile: %{name: "michal"}}, :profile,
                     force_update_on_change: false)
    assert changeset.repo_opts == []

    changeset = cast(%Author{profile: %{name: "michal"}}, %{name: "michal"}, :profile,
                     force_update_on_change: true)
    assert changeset.repo_opts == []
  end

  test "cast has_one with optional" do
    changeset = cast(%Author{profile: %Profile{id: "id"}}, %{"profile" => nil}, :profile)
    assert changeset.changes.profile == nil
    assert changeset.valid?
  end

  test "cast has_one with custom changeset" do
    changeset = cast(%Author{}, %{"profile" => %{}}, :profile, with: &Profile.optional_changeset/2)
    assert (changeset.types.profile |> elem(1)).on_cast == &Profile.optional_changeset/2
    profile = changeset.changes.profile
    assert profile.data.__meta__.source == "users_profiles"
    assert profile.changes == %{}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?
  end
  
  test "cast has_one with custom changeset specified with mfa" do
    changeset = cast(%Author{}, %{"profile" => %{}}, :profile, with: {Profile, :failing_changeset, ["test"]})

    assert changeset.changes.profile.errors == [name: {"test", []}]
    refute changeset.valid?
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

  test "cast has_one discards changesets marked as ignore" do
    changeset = cast(%Author{},
                     %{"profile" => %{name: "michal", id: "id", action: :ignore}},
                     :profile, with: &Profile.set_action/2)
    assert changeset.changes == %{}
  end

  test "cast has_one with empty parameters" do
    changeset = cast(%Author{profile: nil}, %{}, :profile)
    assert changeset.changes == %{}

    changeset = cast(%Author{}, %{}, :profile, required: true)
    assert changeset.changes == %{}

    changeset = cast(%Author{profile: %Profile{}}, %{}, :profile, required: true)
    assert changeset.changes == %{}
  end

  test "cast has_one with on_replace: :raise" do
    schema = %Author{raise_profile: %Profile{id: 1}}

    params = %{"raise_profile" => %{"name" => "jose", "id" => "1"}}
    changeset = cast(schema, params, :raise_profile)
    assert changeset.changes.raise_profile.action == :update

    params = %{"raise_profile" => nil}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(schema, params, :raise_profile)
    end

    params = %{"raise_profile" => %{"name" => "new", "id" => 2}}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(schema, params, :raise_profile)
    end
  end

  test "cast has_one with on_replace: :mark_as_invalid" do
    schema = %Author{invalid_profile: %Profile{id: 1}}

    changeset = cast(schema, %{"invalid_profile" => nil}, :invalid_profile)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: {"is invalid", [validation: :assoc, type: :map]}]
    refute changeset.valid?

    changeset = cast(schema, %{"invalid_profile" => %{"id" => 2}}, :invalid_profile)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: {"is invalid", [validation: :assoc, type: :map]}]
    refute changeset.valid?

    changeset = cast(schema, %{"invalid_profile" => nil}, :invalid_profile, invalid_message: "a custom message")
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: {"a custom message", [validation: :assoc, type: :map]}]
    refute changeset.valid?
  end

  test "cast has_one with keyword defaults" do
    {:ok, schema} = TestRepo.insert(%Author{title: "Title", profile: nil})

    changeset = cast(schema, %{"profile" => %{id: 2}}, :profile)
    assert changeset.changes.profile.data.name == "default"
    assert changeset.changes.profile.changes == %{id: 2}
  end

  test "cast has_one with atom defaults" do
    {:ok, schema} = TestRepo.insert(%Author{title: "Title", invalid_profile: nil})

    changeset = cast(schema, %{"invalid_profile" => %{name: "Jose"}}, :invalid_profile)
    assert_received {:defaults, %Profile{id: nil}, %Author{title: "Title"}, :default}
    assert changeset.changes.invalid_profile.data.id == 13
    assert changeset.changes.invalid_profile.changes == %{name: "Jose"}
  end

  test "cast has_one with MFA defaults" do
    {:ok, schema} = TestRepo.insert(%Author{title: "Title", update_profile: nil})

    changeset = cast(schema, %{"update_profile" => %{name: "Jose"}}, :update_profile)
    assert_received {:defaults, %Profile{id: nil}, %Author{title: "Title"}, :extra}
    assert changeset.changes.update_profile.data.id == 13
    assert changeset.changes.update_profile.changes == %{name: "Jose"}
  end

  test "cast has_one with on_replace: :update" do
    {:ok, schema} = TestRepo.insert(%Author{title: "Title",
      update_profile: %Profile{id: 1, name: "Enio"}})

    changeset = cast(schema, %{"update_profile" => %{id: 2, name: "Jose"}}, :update_profile)
    assert changeset.changes.update_profile.changes == %{name: "Jose", id: 2}
    assert changeset.changes.update_profile.action == :update
    assert changeset.errors == []
    assert changeset.valid?
  end

  test "raises when :update is used on has_many" do
    error_message = ~r"invalid `:on_replace` option for :tags. The only valid options are"

    assert_raise ArgumentError, error_message, fn ->
      defmodule Topic do
        use Ecto.Schema

        schema "topics" do
          has_many :tags, Tag, on_replace: :update
        end
      end
    end
  end

  test "cast has_one twice" do
    schema = %Author{}
    params = %{profile: %{name: "Bruce Wayne", id: 1}}
    schema = cast(schema, params, :profile) |> Changeset.apply_changes
    params = %{profile: %{name: "Batman", id: 1}}
    changeset = cast(schema, params, :profile)
    changeset = cast(changeset, params, :profile)
    assert changeset.valid?

    schema = %Author{}
    params = %{profile: %{name: "Bruce Wayne"}}
    changeset = cast(schema, params, :profile)
    changeset = cast(changeset, params, :profile)
    assert changeset.valid?
  end

  ## cast has_many

  test "cast has_many with only new schemas" do
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

  test "cast has_many with empty posts" do
    assert cast(%Author{}, %{"posts" => []}, :posts).changes == %{posts: []}
    assert cast(%Author{posts: []}, %{"posts" => []}, :posts).changes == %{}

    loaded = put_in %Author{}.__meta__.state, :loaded
    assert_raise RuntimeError, ~r"attempting to cast or change association `posts` .* that was not loaded", fn ->
      cast(loaded, %{"posts" => []}, :posts)
    end
    assert cast(loaded, %{}, :posts).changes == %{}
  end

  # Please note the order is important in this test.
  test "cast has_many changing schemas" do
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

  test "cast has_many with invalid operation" do
    params = %{"posts" => [%{"id" => 1, "title" => "new"}]}
    assert_raise RuntimeError, ~r"cannot update related", fn ->
      cast(%Author{posts: []}, params, :posts, with: &Post.set_action/2)
    end
  end

  test "cast has_many with invalid params" do
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

  test "cast has_many without changes skips" do
    changeset = cast(%Author{posts: [%Post{title: "hello", id: 1}]},
                     %{"posts" => [%{"id" => 1}]}, :posts)
    assert changeset.changes == %{}
  end

  test "cast has_many discards changesets marked as ignore" do
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

  test "cast has_many when required" do
    # Still no error because the loaded association is an empty list
    changeset = cast(%Author{}, %{posts: [%{title: "hello"}]}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.errors == []

    changeset = cast(%Author{}, %{posts: []}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.changes == %{posts: []}
    assert changeset.errors == [posts: {"can't be blank", [validation: :required]}]

    changeset = cast(%Author{posts: [%Post{title: "hello", id: 1}]}, %{posts: []}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.errors == [posts: {"can't be blank", [validation: :required]}]

    changeset = cast(%Author{posts: []}, %{}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.changes == %{}
    assert changeset.errors == [posts: {"can't be blank", [validation: :required]}]

    changeset = cast(%Author{posts: [%Post{title: "hello", id: 1}]}, %{}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.changes == %{}
    assert changeset.errors == []

    changeset = cast(%Author{posts: []}, %{"posts" => nil}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.changes == %{}
    assert changeset.errors == [posts: {"is invalid", [validation: :assoc, type: {:array, :map}]}]
  end

  test "cast has_many with `:force_update_on_change` option" do
    changeset = cast(%Author{}, %{posts: [%{title: "hello"}]}, :posts, force_update_on_change: true)
    assert changeset.repo_opts[:force]

    changeset = cast(%Author{}, %{posts: [%{title: "hello"}]}, :posts, force_update_on_change: false)
    assert changeset.repo_opts == []

    changeset = cast(%Author{posts: [%Post{title: "hello"}]}, %{posts: [%{title: "hello"}]}, :posts,
                     force_update_on_change: true)
    assert changeset.repo_opts == []
  end

  test "cast has_many with empty parameters" do
    changeset = cast(%Author{posts: []}, %{}, :posts)
    assert changeset.changes == %{}

    changeset = cast(%Author{}, %{}, :posts)
    assert changeset.changes == %{}

    changeset = cast(%Author{posts: [%Post{}]}, %{}, :posts)
    assert changeset.changes == %{}
  end

  test "cast has_many with keyword defaults" do
    {:ok, schema} = TestRepo.insert(%Author{title: "Title", posts: []})

    changeset = cast(schema, %{"posts" => [%{id: 2}]}, :posts)
    assert hd(changeset.changes.posts).data.title == "default"
    assert hd(changeset.changes.posts).changes == %{}
  end

  test "cast has_many with MFA defaults" do
    {:ok, schema} = TestRepo.insert(%Author{title: "Title", nilify_posts: []})

    changeset = cast(schema, %{"nilify_posts" => [%{title: "Title"}]}, :nilify_posts)
    assert hd(changeset.changes.nilify_posts).data.id == 13
    assert hd(changeset.changes.nilify_posts).changes == %{title: "Title"}
  end

  test "cast has_many with on_replace: :raise" do
    schema = %Author{raise_posts: [%Post{id: 1}]}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(schema, %{"raise_posts" => []}, :raise_posts)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(schema, %{"raise_posts" => [%{"id" => 2}]}, :raise_posts)
    end
  end

  test "cast has_many with on_replace: :mark_as_invalid" do
    schema = %Author{invalid_posts: [%Post{id: 1}]}

    changeset = cast(schema, %{"invalid_posts" => []}, :invalid_posts)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"is invalid", [validation: :assoc, type: {:array, :map}]}]
    refute changeset.valid?

    changeset = cast(schema, %{"invalid_posts" => [%{"id" => 2}]}, :invalid_posts)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"is invalid", [validation: :assoc, type: {:array, :map}]}]
    refute changeset.valid?
  end

  test "cast has_many twice" do
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

  ## Change

  test "change has_one" do
    assoc = Author.__schema__(:association, :profile)

    assert {:ok, nil, true} = Relation.change(assoc, nil, nil)
    assert {:ok, nil, true} = Relation.change(assoc, nil, %Profile{})

    assoc_schema = %Profile{}
    assoc_schema_changeset = Changeset.change(assoc_schema, name: "michal")

    assert {:ok, changeset, true} =
      Relation.change(assoc, assoc_schema_changeset, nil)
    assert changeset.action == :insert
    assert changeset.changes == %{name: "michal"}

    assert {:ok, changeset, true} =
      Relation.change(assoc, assoc_schema_changeset, assoc_schema)
    assert changeset.action == :update
    assert changeset.changes == %{name: "michal"}

    assert :ignore = Relation.change(assoc, %{assoc_schema_changeset | action: :ignore}, nil)

    empty_changeset = Changeset.change(assoc_schema)
    assert :ignore = Relation.change(assoc, empty_changeset, assoc_schema)

    assoc_with_id = %Profile{id: 2}
    assert {:ok, _, true} =
      Relation.change(assoc, %Profile{id: 1}, assoc_with_id)
  end

  test "change has_one with attributes" do
    assoc = Author.__schema__(:association, :profile)

    assert {:ok, changeset, true} =
      Relation.change(assoc, %{name: "michal"}, nil)
    assert changeset.action == :insert
    assert changeset.changes == %{name: "michal"}

    profile = %Profile{name: "other"} |> Ecto.put_meta(state: :loaded)

    assert {:ok, changeset, true} =
      Relation.change(assoc, %{name: "michal"}, profile)
    assert changeset.action == :update
    assert changeset.changes == %{name: "michal"}

    assert {:ok, changeset, true} =
      Relation.change(assoc, [name: "michal"], profile)
    assert changeset.action == :update
    assert changeset.changes == %{name: "michal"}

    profile = %Profile{name: "other"}

    assert {:ok, changeset, true} =
      Relation.change(assoc, %{name: "michal"}, profile)
    assert changeset.action == :insert
    assert changeset.changes == %{name: "michal"}

    assert {:ok, changeset, true} =
      Relation.change(assoc, [name: "michal"], profile)
    assert changeset.action == :insert
    assert changeset.changes == %{name: "michal"}
  end

  test "change has_one with structs" do
    assoc = Author.__schema__(:association, :profile)
    profile = %Profile{name: "michal"}

    assert {:ok, changeset, true} =
      Relation.change(assoc, profile, nil)
    assert changeset.action == :insert

    assert {:ok, changeset, true} =
      Relation.change(assoc, Ecto.put_meta(profile, state: :loaded), nil)
    assert changeset.action == :update

    assert {:ok, changeset, true} =
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
    assoc_schema = %Profile{id: 1}

    # Adding
    changeset = %{Changeset.change(assoc_schema, name: "michal") | action: :insert}
    {:ok, changeset, _} = Relation.change(assoc, changeset, nil)
    assert changeset.action == :insert

    changeset = %{Changeset.change(assoc_schema) | action: :update}
    {:ok, changeset, _} = Relation.change(assoc, changeset, nil)
    assert changeset.action == :update

    changeset = %{Changeset.change(assoc_schema) | action: :delete}
    {:ok, changeset, _} = Relation.change(assoc, changeset, nil)
    assert changeset.action == :delete

    # Replacing
    changeset = %{Changeset.change(assoc_schema, name: "michal") | action: :insert}
    assert_raise RuntimeError, ~r/cannot insert related/, fn ->
      Relation.change(assoc, changeset, assoc_schema)
    end

    changeset = %{Changeset.change(assoc_schema) | action: :update}
    {:ok, changeset, _} = Relation.change(assoc, changeset, nil)
    assert changeset.action == :update

    changeset = %{Changeset.change(assoc_schema) | action: :delete}
    {:ok, changeset, _} = Relation.change(assoc, changeset, nil)
    assert changeset.action == :delete
  end

  test "change has_one with on_replace: :raise" do
    assoc_schema = %Profile{id: 1}
    base_changeset = Changeset.change(%Author{raise_profile: assoc_schema})

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :raise_profile, nil)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :raise_profile, %Profile{id: 2})
    end
  end

  test "change has_one with on_replace: :mark_as_invalid" do
    assoc_schema = %Profile{id: 1}
    base_changeset = Changeset.change(%Author{invalid_profile: assoc_schema})

    changeset = Changeset.put_assoc(base_changeset, :invalid_profile, nil)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: {"is invalid", [type: :map]}]
    refute changeset.valid?

    changeset = Changeset.put_assoc(base_changeset, :invalid_profile, %Profile{id: 2})
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: {"is invalid", [type: :map]}]
    refute changeset.valid?
  end

  test "change has_many" do
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
    assert :ignore = Relation.change(assoc, [empty_changeset], [assoc_schema])
  end

  test "change has_many with attributes" do
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

    post = %Post{title: "other"}

    assert {:ok, [changeset], true} =
      Relation.change(assoc, [%{title: "hello"}], [post])
    assert changeset.action == :insert
    assert changeset.changes == %{title: "hello"}

    assert {:ok, [changeset], true} =
      Relation.change(assoc, [[title: "hello"]], [post])
    assert changeset.action == :insert
    assert changeset.changes == %{title: "hello"}
  end

  test "change has_many with structs" do
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

  test "change has_many with on_replace: :nilify" do
    post = %Post{id: 1, author_id: 5}
    changeset = cast(%Author{nilify_posts: [post]}, %{"nilify_posts" => []}, :nilify_posts)
    [post_change] = changeset.changes.nilify_posts
    assert post_change.action == :replace
    assert post_change.changes == %{}
  end

  test "change has_many with on_replace: :raise" do
    assoc_schema = %Post{id: 1}
    base_changeset = Changeset.change(%Author{raise_posts: [assoc_schema]})

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :raise_posts, [])
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :raise_posts, [%Post{id: 2}])
    end
  end

  test "change has_many with on_replace: :mark_as_invalid" do
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

  ## Other

  test "validate_required/3 with has_many raises" do
    import ExUnit.CaptureIO

    base_changeset = Changeset.change(%Author{})

    assert capture_io(:stderr, fn ->
      changeset = Changeset.validate_required(base_changeset, :posts)
      assert changeset.valid?
    end) =~ ~r/attempting to validate has_many association :posts/
  end

  test "put_assoc/4 with has_one" do
    base_changeset = Changeset.change(%Author{})

    changeset = Changeset.put_assoc(base_changeset, :profile, %{name: "michal"})
    assert %Ecto.Changeset{} = changeset.changes.profile
    assert changeset.changes.profile.action == :insert
    assert changeset.changes.profile.data.__meta__.source == "users_profiles"

    changeset = Changeset.put_assoc(base_changeset, :profile, [name: "michal"])
    assert %Ecto.Changeset{} = changeset.changes.profile
    assert changeset.changes.profile.action == :insert
    assert changeset.changes.profile.data.__meta__.source == "users_profiles"

    changeset = Changeset.put_assoc(base_changeset, :profile, %Profile{name: "michal"})
    assert %Ecto.Changeset{} = changeset.changes.profile
    assert changeset.changes.profile.action == :insert
    assert changeset.changes.profile.data.__meta__.source == "profiles"

    base_changeset = Changeset.change(%Author{profile: %Profile{name: "michal"}})
    empty_update_changeset = Changeset.change(%Profile{name: "michal"})

    changeset = Changeset.put_assoc(base_changeset, :profile, empty_update_changeset)
    refute Map.has_key?(changeset.changes, :profile)
  end

  test "put_assoc/4 with has_one and empty" do
    # On unloaded
    changeset =
      %Author{}
      |> Changeset.change()
      |> Changeset.put_assoc(:profile, nil)

    assert Map.has_key?(changeset.changes, :profile)

    # On empty
    changeset =
      %Author{profile: nil}
      |> Changeset.change()
      |> Changeset.put_assoc(:profile, nil)

    refute Map.has_key?(changeset.changes, :profile)
  end

  test "put_change/3 with has_one" do
    changeset = Changeset.change(%Author{}, profile: %{name: "michal"})
    assert %Ecto.Changeset{} = changeset.changes.profile
    assert changeset.changes.profile.action == :insert

    base_changeset = Changeset.change(%Author{})
    changeset = Changeset.put_change(base_changeset, :profile, [name: "michal"])
    assert %Ecto.Changeset{} = changeset.changes.profile
    assert changeset.changes.profile.action == :insert

    changeset = Changeset.put_change(base_changeset, :profile, %Profile{name: "michal"})
    assert %Ecto.Changeset{} = changeset.changes.profile
    assert changeset.changes.profile.action == :insert

    base_changeset = Changeset.change(%Author{profile: %Profile{name: "michal"}})
    empty_update_changeset = Changeset.change(%Profile{name: "michal"})

    changeset = Changeset.put_change(base_changeset, :profile, empty_update_changeset)
    refute Map.has_key?(changeset.changes, :profile)
  end

  test "put_assoc/4 with has_many" do
    base_changeset = Changeset.change(%Author{})

    changeset = Changeset.put_assoc(base_changeset, :posts, [%{title: "hello"}])
    assert [%Ecto.Changeset{}] = changeset.changes.posts
    assert hd(changeset.changes.posts).action == :insert

    changeset = Changeset.put_assoc(base_changeset, :posts, [[title: "hello"]])
    assert [%Ecto.Changeset{}] = changeset.changes.posts
    assert hd(changeset.changes.posts).action == :insert

    changeset = Changeset.put_assoc(base_changeset, :posts, [%Post{title: "hello"}])
    assert [%Ecto.Changeset{}] = changeset.changes.posts
    assert hd(changeset.changes.posts).action == :insert

    base_changeset = Changeset.change(%Author{posts: [%Post{title: "hello"}]})
    empty_update_changeset = Changeset.change(%Post{title: "hello"})

    changeset = Changeset.put_assoc(base_changeset, :posts, [empty_update_changeset])
    refute Map.has_key?(changeset.changes, :posts)
  end

  test "put_assoc/4 with has_many and empty" do
    # On unloaded
    changeset =
      %Author{}
      |> Changeset.change()
      |> Changeset.put_assoc(:posts, [])

    assert Map.has_key?(changeset.changes, :posts)

    # On empty
    changeset =
      %Author{posts: []}
      |> Changeset.change()
      |> Changeset.put_assoc(:posts, [])

    refute Map.has_key?(changeset.changes, :posts)
  end

  test "put_change/3 with has_many" do
    changeset = Changeset.change(%Author{}, posts: [%{title: "hello"}])
    assert [%Ecto.Changeset{}] = changeset.changes.posts
    assert hd(changeset.changes.posts).action == :insert

    base_changeset = Changeset.change(%Author{})
    changeset = Changeset.put_change(base_changeset, :posts, [[title: "hello"]])
    assert [%Ecto.Changeset{}] = changeset.changes.posts
    assert hd(changeset.changes.posts).action == :insert

    changeset = Changeset.put_change(base_changeset, :posts, [%Post{title: "hello"}])
    assert [%Ecto.Changeset{}] = changeset.changes.posts
    assert hd(changeset.changes.posts).action == :insert

    base_changeset = Changeset.change(%Author{posts: [%Post{title: "hello"}]})
    empty_update_changeset = Changeset.change(%Post{title: "hello"})

    changeset = Changeset.put_change(base_changeset, :posts, [empty_update_changeset])
    refute Map.has_key?(changeset.changes, :posts)
  end

  test "put_assoc/4 raises on invalid changeset" do
    assert_raise ArgumentError, ~r/expected changeset data to be a Elixir.Ecto.Changeset.HasAssocTest.Profile/, fn ->
      Changeset.change(%Author{}, profile: %Author{})
    end

    assert_raise ArgumentError, ~r/expected changeset data to be a Elixir.Ecto.Changeset.HasAssocTest.Post/, fn ->
      Changeset.change(%Author{}, posts: [%Author{}])
    end
  end

  test "put_assoc/4 when replacing" do
    profile = %Profile{id: 1, name: "michal"} |> Ecto.put_meta(state: :loaded)
    base_changeset = Changeset.change(%Author{profile: profile})

    changeset = Changeset.put_assoc(base_changeset, :profile, %{name: "michal"})
    assert %Ecto.Changeset{} = changeset.changes.profile
    assert changeset.changes.profile.action == :insert
    assert changeset.changes.profile.changes == %{name: "michal"}

    changeset = Changeset.put_assoc(base_changeset, :profile, %Profile{name: "michal"})
    assert %Ecto.Changeset{} = changeset.changes.profile
    assert changeset.changes.profile.action == :insert
    assert changeset.changes.profile.changes == %{}

    changeset = Changeset.put_assoc(base_changeset, :profile, %{id: 1, name: "michal"})
    refute Map.has_key?(changeset.changes, :profile)
    changeset = Changeset.put_assoc(base_changeset, :profile, %Profile{id: 1, name: "michal"})
    refute Map.has_key?(changeset.changes, :profile)

    changeset = Changeset.put_assoc(base_changeset, :profile, %{id: 1, name: "jose"})
    assert %Ecto.Changeset{} = changeset.changes.profile
    assert changeset.changes.profile.action == :update
    assert changeset.changes.profile.changes == %{name: "jose"}
  end

  test "get_field/3, fetch_field/2 with has one" do
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
    assert Changeset.fetch_field(changeset, :profile) == {:data, profile}

    changeset = Changeset.change(%Author{})
    assert Changeset.get_field(changeset, :profile) == nil
    assert Changeset.fetch_field(changeset, :profile) == {:data, nil}

    schema = put_in(%Author{}.__meta__.state, :loaded)
    changeset = Changeset.change(schema)
    assert_raise RuntimeError, ~r"Please preload", fn ->
      Changeset.get_field(changeset, :profile)
    end
    assert_raise RuntimeError, ~r"Please preload", fn ->
      Changeset.fetch_field(changeset, :profile)
    end
  end

  test "get_field/3, fetch_field/2 with has many" do
    post = %Post{id: 1}

    changeset =
      %Author{posts: [post]}
      |> Changeset.change
    assert Changeset.get_field(changeset, :posts) == [post]
    assert Changeset.fetch_field(changeset, :posts) == {:data, [post]}

    post_changeset = Changeset.change(post, title: "updated")
    changeset =
      %Author{posts: [post]}
      |> Changeset.change
      |> Changeset.put_assoc(:posts, [post_changeset])
    assert Changeset.get_field(changeset, :posts) == [%{post | title: "updated"}]
    assert Changeset.fetch_field(changeset, :posts) == {:changes, [%{post | title: "updated"}]}

    post_changeset = %{Changeset.change(post) | action: :delete}
    changeset =
      %Author{posts: [post]}
      |> Changeset.change
      |> Changeset.put_assoc(:posts, [post_changeset])
    assert Changeset.get_field(changeset, :posts) == []
    assert Changeset.fetch_field(changeset, :posts) == {:changes, []}

    changeset = Changeset.change(%Author{})
    assert Changeset.get_field(changeset, :posts) == []
    assert Changeset.fetch_field(changeset, :posts) == {:data, []}

    schema = put_in(%Author{}.__meta__.state, :loaded)
    changeset = Changeset.change(schema)
    assert_raise RuntimeError, ~r"Please preload", fn ->
      Changeset.get_field(changeset, :posts)
    end
    assert_raise RuntimeError, ~r"Please preload", fn ->
      Changeset.fetch_field(changeset, :posts)
    end
  end

  test "apply_changes" do
    assoc = Author.__schema__(:association, :profile)

    changeset = Changeset.change(%Profile{}, name: "michal")
    schema = Relation.apply_changes(assoc, changeset)
    assert schema == %Profile{name: "michal"}

    changeset1 = Changeset.change(%Post{}, title: "hello")
    changeset2 = %{changeset1 | action: :delete}
    assert Relation.apply_changes(assoc, changeset2) == nil

    assoc = Author.__schema__(:association, :posts)
    [schema] = Relation.apply_changes(assoc, [changeset1, changeset2])
    assert schema == %Post{title: "hello"}
  end

  ## traverse_errors

  test "traverses changeset errors with has_one when required" do
    changeset = cast(%Author{}, %{profile: %{}}, :profile, required: true)
    assert changeset.errors == []
    assert Changeset.traverse_errors(changeset, &(&1)) == %{}

    changeset = cast(%Author{}, %{}, :profile, required: true)
    assert changeset.errors == [profile: {"can't be blank", [validation: :required]}]
    assert Changeset.traverse_errors(changeset, &(&1)) == %{profile: [{"can't be blank", [validation: :required]}]}

    changeset = cast(%Author{}, %{"profile" => nil}, :profile, required: true)
    assert changeset.errors == [profile: {"can't be blank", [validation: :required]}]
    assert Changeset.traverse_errors(changeset, &(&1)) == %{profile: [{"can't be blank", [validation: :required]}]}

    changeset = cast(%Author{}, %{}, :profile, required: true, required_message: "a custom message")
    assert changeset.errors == [profile: {"a custom message", [validation: :required]}]
    assert Changeset.traverse_errors(changeset, &(&1)) == %{profile: [{"a custom message", [validation: :required]}]}

    changeset = cast(%Author{}, %{"profile" => %{name: nil}}, :profile, required: true)
    assert changeset.errors == []
    assert Changeset.traverse_errors(changeset, &(&1)) == %{profile: %{name: [{"can't be blank", [validation: :required]}]}}
  end

  test "traverses changeset errors with has_many when required" do
    changeset = cast(%Author{}, %{posts: [%{title: "hello"}]}, :posts, required: true)
    assert changeset.errors == []
    assert Changeset.traverse_errors(changeset, &(&1)) == %{}

    changeset = cast(%Author{}, %{posts: [%{title: nil}]}, :posts, required: true)
    assert changeset.errors == []
    assert Changeset.traverse_errors(changeset, &(&1)) == %{posts: [%{title: [{"can't be blank", [validation: :required]}]}]}

    changeset = cast(%Author{posts: []}, %{}, :posts, required: true)
    assert changeset.errors == [posts: {"can't be blank", [validation: :required]}]
    assert Changeset.traverse_errors(changeset, &(&1)) == %{posts: [{"can't be blank", [validation: :required]}]}

    changeset = cast(%Author{posts: []}, %{"posts" => nil}, :posts, required: true)
    assert changeset.errors == [posts: {"is invalid", [validation: :assoc, type: {:array, :map}]}]
    assert Changeset.traverse_errors(changeset, &(&1)) == %{posts: [{"is invalid", [validation: :assoc, type: {:array, :map}]}]}

    changeset = cast(%Author{}, %{posts: []}, :posts, required: true)
    assert changeset.errors == [posts: {"can't be blank", [validation: :required]}]
    assert Changeset.traverse_errors(changeset, &(&1)) == %{posts: [{"can't be blank", [validation: :required]}]}
  end

  ## traverse_validations

  test "traverses changeset validations with has_one" do
    changeset = cast(%Author{}, %{profile: %{}}, :profile)
    assert Changeset.traverse_validations(changeset, &(&1)) == %{profile: %{name: [length: [min: 3]]}}
  end

  test "traverses changeset validations with has_many" do
    changeset = cast(%Author{}, %{posts: [%{}]}, :posts)
    assert Changeset.traverse_validations(changeset, &(&1)) == %{posts: [%{title: [length: [min: 3]]}]}
  end
end
