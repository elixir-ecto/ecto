defmodule Ecto.Changeset.EmbeddedTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Ecto.Changeset.Relation
  alias Ecto.Embedded
  alias Ecto.TestRepo

  alias __MODULE__.Author
  alias __MODULE__.Profile
  alias __MODULE__.Post
  alias __MODULE__.Nested

  defmodule Author do
    use Ecto.Schema

    schema "authors" do
      field :name, :string
      embeds_one :profile, Profile, on_replace: :delete
      embeds_one :raise_profile, Profile, on_replace: :raise
      embeds_one :invalid_profile, Profile, on_replace: :mark_as_invalid
      embeds_one :update_profile, Profile, on_replace: :update
      embeds_one :inline_profile, Profile do
        field :name, :string
      end
      embeds_one :nested, Nested
      embeds_many :posts, Post, on_replace: :delete
      embeds_many :raise_posts, Post, on_replace: :raise
      embeds_many :invalid_posts, Post, on_replace: :mark_as_invalid
      embeds_many :inline_posts, Post do
        field :title, :string
      end
    end
  end

  defmodule Post do
    use Ecto.Schema
    import Ecto.Changeset

    schema "posts" do
      field :title, :string
    end

    def changeset(schema, params) do
      cast(schema, params, ~w(title)a)
      |> validate_required(:title)
      |> validate_length(:title, min: 3)
    end

    def optional_changeset(schema, params) do
      cast(schema, params, ~w(title)a)
    end

    def set_action(schema, params) do
      changeset(schema, params)
      |> Map.put(:action, Map.get(params, :action, :update))
    end
  end

  defmodule Profile do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :name
    end

    def changeset(schema, params) do
      cast(schema, params, ~w(name id)a)
      |> validate_required(:name)
      |> validate_length(:name, min: 3)
    end

    def optional_changeset(schema, params) do
      cast(schema, params, ~w(name)a)
    end

    def set_action(schema, params) do
      changeset(schema, params)
      |> Map.put(:action, Map.get(params, :action, :update))
    end
  end

  defmodule Nested do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      embeds_one :profile, Profile
    end

    def changeset(schema, params) do
      cast(schema, params, [])
      |> cast_embed(:profile)
    end
  end

  defp cast(schema, params, embed, opts \\ []) do
    schema
    |> Changeset.cast(params, ~w())
    |> Changeset.cast_embed(embed, opts)
  end

  ## Cast embeds one

  test "cast embeds_one with valid params" do
    changeset = cast(%Author{}, %{"profile" => %{"name" => "michal"}}, :profile)
    profile = changeset.changes.profile
    assert profile.changes == %{name: "michal"}
    assert profile.errors == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast embeds_one with invalid params" do
    changeset = cast(%Author{}, %{"profile" => %{}}, :profile)
    assert changeset.changes.profile.changes == %{}
    assert changeset.changes.profile.errors  == [name: {"can't be blank", [validation: :required]}]
    assert changeset.changes.profile.action  == :insert
    refute changeset.changes.profile.valid?
    refute changeset.valid?

    # string
    changeset = cast(%Author{}, %{"profile" => "value"}, :profile, required: true)
    assert changeset.errors == [profile: {"is invalid", [validation: :embed, type: :map]}]
    refute changeset.valid?

    # list
    changeset = cast(%Author{}, %{"profile" => [%{"name" => "michal"}]}, :profile)
    assert changeset.changes == %{}
    assert changeset.errors  == [profile: {"is invalid", [validation: :embed, type: :map]}]
  end

  test "cast embeds_one with existing struct updating" do
    changeset = cast(%Author{profile: %Profile{name: "michal", id: "michal"}},
                     %{"profile" => %{"name" => "new", "id" => "michal"}}, :profile)

    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.action  == :update
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast embeds_one with existing struct updating from atom params" do
    # Emulate atom params from nested associations
    changeset = Changeset.cast(%Author{profile: %Profile{name: "michal", id: "michal"}}, %{}, ~w())
    changeset = put_in changeset.params, %{"profile" => %{name: "new", id: "michal"}}

    changeset = Changeset.cast_embed(changeset, :profile, [])
    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.action  == :update
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast embeds_one with existing struct replacing" do
    changeset = cast(%Author{profile: %Profile{name: "michal", id: "michal"}},
                     %{"profile" => %{"name" => "new"}}, :profile)

    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?

    changeset = cast(%Author{profile: %Profile{name: "michal", id: "michal"}},
                     %{"profile" => %{"name" => "new", "id" => "new"}}, :profile)
    profile = changeset.changes.profile
    assert profile.changes == %{name: "new", id: "new"}
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

  test "cast embeds_one without changes skips" do
    changeset = cast(%Author{profile: %Profile{name: "michal", id: "michal"}},
                     %{"profile" => %{"id" => "michal"}}, :profile)
    assert changeset.changes == %{}
    assert changeset.errors == []
  end

  test "cast embeds_on discards changesets marked as ignore" do
    changeset = cast(%Author{},
                     %{"profile" => %{name: "michal", id: "id", action: :ignore}},
                     :profile, with: &Profile.set_action/2)
    assert changeset.changes == %{}
  end

  test "cast embeds_one when required" do
    changeset = cast(%Author{profile: nil}, %{}, :profile, required: true)
    assert changeset.required == [:profile]
    assert changeset.changes == %{}
    assert changeset.errors == [profile: {"can't be blank", [validation: :required]}]

    changeset = cast(%Author{profile: nil}, %{}, :profile, required: true, required_message: "a custom message")
    assert changeset.required == [:profile]
    assert changeset.changes == %{}
    assert changeset.errors == [profile: {"a custom message", [validation: :required]}]

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

  test "cast embeds_one with optional" do
    changeset = cast(%Author{profile: %Profile{id: "id"}}, %{"profile" => nil}, :profile)
    assert changeset.changes.profile == nil
    assert changeset.valid?
  end

  test "cast embeds_one with `:force_update_on_change` option" do
    changeset = cast(%Author{profile: %Profile{id: "id"}}, %{profile: nil}, :profile,
                     force_update_on_change: true)
    assert changeset.repo_opts[:force]

    changeset = cast(%Author{profile: %Profile{id: "id"}}, %{profile: nil}, :profile,
                     force_update_on_change: false)
    assert changeset.repo_opts == []

    changeset = cast(%Author{profile: nil}, %{profile: nil}, :profile, force_update_on_change: true)
    assert changeset.repo_opts == []
  end

  test "cast embeds_one with custom changeset" do
    changeset = cast(%Author{}, %{"profile" => %{"name" => "michal"}}, :profile,
                     with: &Profile.optional_changeset/2)

    assert (changeset.types.profile |> elem(1)).on_cast == &Profile.optional_changeset/2
    profile = changeset.changes.profile
    assert profile.changes == %{name: "michal"}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast embeds_one keeps appropriate action from changeset" do
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

  test "cast embeds_one with empty parameters" do
    changeset = cast(%Author{profile: nil}, %{}, :profile)
    assert changeset.changes == %{}

    changeset = cast(%Author{profile: %Profile{}}, %{}, :profile)
    assert changeset.changes == %{}
  end

  test "cast embeds_one with on_replace: :raise" do
    schema  = %Author{raise_profile: %Profile{id: 1}}
    params = %{"raise_profile" => %{"name" => "jose", "id" => 1}}

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

  test "cast embeds_one with on_replace: :mark_as_invalid" do
    schema = %Author{invalid_profile: %Profile{id: 1}}

    changeset = cast(schema, %{"invalid_profile" => nil}, :invalid_profile)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: {"is invalid", [validation: :embed, type: :map]}]
    refute changeset.valid?

    changeset = cast(schema, %{"invalid_profile" => %{"id" => 2}}, :invalid_profile)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: {"is invalid", [validation: :embed, type: :map]}]
    refute changeset.valid?

    changeset = cast(schema, %{"invalid_profile" => nil}, :invalid_profile, invalid_message: "a custom message")
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: {"a custom message", [validation: :embed, type: :map]}]
    refute changeset.valid?
  end

  test "cast embeds_one with on_replace: :update" do
    {:ok, schema} = TestRepo.insert(%Author{name: "Enio",
      update_profile: %Profile{name: "Enio"}})

    changeset = cast(schema, %{"update_profile" => %{name: "Jose"}}, :update_profile)
    assert changeset.changes.update_profile.changes == %{name: "Jose"}
    assert changeset.changes.update_profile.action == :update
    assert changeset.errors == []
    assert changeset.valid?
  end

  test "raises when :update is used on embeds_many" do
    error_message = "invalid `:on_replace` option for :tags. The only valid " <>
      "options are: `:raise`, `:mark_as_invalid`, `:delete`"
    assert_raise ArgumentError, error_message, fn ->
      defmodule Topic do
        use Ecto.Schema

        schema "topics" do
          embeds_many :tags, Tag, on_replace: :update
        end
      end
    end
  end

  test "cast inline embeds_one with valid params" do
    changeset = cast(%Author{}, %{"inline_profile" => %{"name" => "michal"}},
                     :inline_profile, with: &Profile.changeset/2)
    profile = changeset.changes.inline_profile
    assert profile.changes == %{name: "michal"}
    assert profile.errors == []
    assert profile.action == :insert
    assert profile.valid?
    assert changeset.valid?
  end

  ## cast embeds many

  test "cast embeds_many with only new schemas" do
    changeset = cast(%Author{}, %{"posts" => [%{"title" => "hello"}]}, :posts)
    [post_change] = changeset.changes.posts
    assert post_change.changes == %{title: "hello"}
    assert post_change.errors  == []
    assert post_change.action  == :insert
    assert post_change.valid?
    assert changeset.valid?
  end

  test "cast embeds_many with map" do
    changeset = cast(%Author{}, %{"posts" => %{0 => %{"title" => "hello"}}}, :posts)
    [post_change] = changeset.changes.posts
    assert post_change.changes == %{title: "hello"}
    assert post_change.errors  == []
    assert post_change.action  == :insert
    assert post_change.valid?
    assert changeset.valid?
  end

  test "cast embeds_many with custom changeset" do
    changeset = cast(%Author{}, %{"posts" => [%{"title" => "hello"}]},
                     :posts, with: &Post.optional_changeset/2)
    [post_change] = changeset.changes.posts
    assert post_change.changes == %{title: "hello"}
    assert post_change.errors  == []
    assert post_change.action  == :insert
    assert post_change.valid?
    assert changeset.valid?
  end

  # Please note the order is important in this test.
  test "cast embeds_many changing schemas" do
    posts = [%Post{title: "first",   id: 1},
             %Post{title: "second", id: 2},
             %Post{title: "third",   id: 3}]
    params = [%{"title" => "new"},
              %{"id" => "2", "title" => nil},
              %{"id" => "3", "title" => "new name"}]

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

  test "cast embeds_many with invalid operation" do
    params = %{"posts" => [%{"id" => 1, "title" => "new"}]}
    assert_raise RuntimeError, ~r"cannot update related", fn ->
      cast(%Author{posts: []}, params, :posts, with: &Post.set_action/2)
    end
  end

  test "cast embeds_many with invalid params" do
    changeset = cast(%Author{}, %{"posts" => "value"}, :posts)
    assert changeset.errors == [posts: {"is invalid", [validation: :embed, type: {:array, :map}]}]
    refute changeset.valid?

    changeset = cast(%Author{}, %{"posts" => ["value"]}, :posts)
    assert changeset.errors == [posts: {"is invalid", [validation: :embed, type: {:array, :map}]}]
    refute changeset.valid?

    changeset = cast(%Author{}, %{"posts" => nil}, :posts)
    assert changeset.errors == [posts: {"is invalid", [validation: :embed, type: {:array, :map}]}]
    refute changeset.valid?

    changeset = cast(%Author{}, %{"posts" => %{"id" => "invalid"}}, :posts)
    assert changeset.errors == [posts: {"is invalid", [validation: :embed, type: {:array, :map}]}]
    refute changeset.valid?
  end

  test "cast embeds_many without changes skips" do
    changeset = cast(%Author{posts: [%Post{title: "hello", id: 1}]},
                     %{"posts" => [%{"id" => 1}]}, :posts)

    refute Map.has_key?(changeset.changes, :posts)
  end

  test "cast embeds_many discards changesets marked as ignore" do
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

  test "cast embeds_many when required" do
    changeset = cast(%Author{posts: []}, %{}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.changes == %{}
    assert changeset.errors == [posts: {"can't be blank", [validation: :required]}]

    changeset = cast(%Author{posts: []}, %{"posts" => nil}, :posts, required: true)
    assert changeset.changes == %{}
    assert changeset.errors == [posts: {"is invalid", [validation: :embed, type: {:array, :map}]}]
  end

  test "cast embeds_many with `:force_update_on_change` option" do
    params = [%{title: "hello"}]
    changeset = cast(%Author{}, %{posts: params}, :posts, force_update_on_change: true)
    assert changeset.repo_opts[:force]

    changeset = cast(%Author{}, %{posts: params}, :posts, force_update_on_change: false)
    assert changeset.repo_opts == []

    changeset = cast(%Author{posts: [%Post{title: "hello"}]}, %{posts: params}, :posts,
                     force_update_on_change: true)
    assert changeset.repo_opts == []
  end

  test "cast embeds_many with empty parameters" do
    changeset = cast(%Author{posts: []}, %{}, :posts)
    assert changeset.changes == %{}

    changeset = cast(%Author{posts: [%Post{}]}, %{}, :posts)
    assert changeset.changes == %{}
  end

  test "cast embeds_many with on_replace: :raise" do
    schema = %Author{raise_posts: [%Post{id: 1}]}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(schema, %{"raise_posts" => []}, :raise_posts)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(schema, %{"raise_posts" => [%{"id" => 2}]}, :raise_posts)
    end
  end

  test "cast embeds_many with on_replace: :mark_as_invalid" do
    schema = %Author{invalid_posts: [%Post{id: 1}]}

    changeset = cast(schema, %{"invalid_posts" => []}, :invalid_posts)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"is invalid", [validation: :embed, type: {:array, :map}]}]
    refute changeset.valid?

    changeset = cast(schema, %{"invalid_posts" => [%{"id" => 2}]}, :invalid_posts)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"is invalid", [validation: :embed, type: {:array, :map}]}]
    refute changeset.valid?
  end

  test "cast inline embeds_many with valid params" do
    changeset = cast(%Author{}, %{"inline_posts" => [%{"title" => "hello"}]},
      :inline_posts, with: &Post.changeset/2)
    [post] = changeset.changes.inline_posts
    assert post.changes == %{title: "hello"}
    assert post.errors == []
    assert post.action  == :insert
    assert post.valid?
    assert changeset.valid?
  end

  ## Others

  test "validate_required/3 with has_many raises" do
    base_changeset = Changeset.change(%Author{})

    assert ExUnit.CaptureIO.capture_io(:stderr, fn ->
      changeset = Changeset.validate_required(base_changeset, :posts)
      assert changeset.valid?
    end) =~ ~r/attempting to validate embed_many field/
  end

  test "change embeds_one" do
    embed = Author.__schema__(:embed, :profile)

    assert {:ok, nil, true} = Relation.change(embed, nil, nil)
    assert {:ok, nil, true} = Relation.change(embed, nil, %Profile{})

    embed_schema = %Profile{}
    embed_schema_changeset = Changeset.change(embed_schema, name: "michal")

    assert {:ok, changeset, true} =
      Relation.change(embed, embed_schema_changeset, nil)
    assert changeset.action == :insert
    assert changeset.changes == %{name: "michal"}

    assert {:ok, changeset, true} =
      Relation.change(embed, embed_schema_changeset, embed_schema)
    assert changeset.action == :update
    assert changeset.changes == %{name: "michal"}

    assert :ignore = Relation.change(embed, %{embed_schema_changeset | action: :ignore}, nil)

    empty_changeset = Changeset.change(embed_schema)
    assert :ignore = Relation.change(embed, empty_changeset, embed_schema)

    embed_with_id = %Profile{id: 2}
    assert {:ok, _, true} =
      Relation.change(embed, %Profile{id: 1}, embed_with_id)
  end

  test "change embeds_one with attributes" do
    embed = Author.__schema__(:embed, :profile)

    assert {:ok, changeset, true} =
      Relation.change(embed, %{name: "michal"}, nil)
    assert changeset.action == :insert
    assert changeset.changes == %{name: "michal"}

    profile = %Profile{name: "other"}

    assert {:ok, changeset, true} =
      Relation.change(embed, %{name: "michal"}, profile)
    assert changeset.action == :update
    assert changeset.changes == %{name: "michal"}

    assert {:ok, changeset, true} =
      Relation.change(embed, [name: "michal"], profile)
    assert changeset.action == :update
    assert changeset.changes == %{name: "michal"}
  end

  test "change embeds_one with structs" do
    embed = Author.__schema__(:embed, :profile)
    profile = %Profile{name: "michal"}

    assert {:ok, changeset, true} =
      Relation.change(embed, profile, nil)
    assert changeset.action == :insert
  end

  test "change embeds_one keeps appropriate action from changeset" do
    embed = Author.__schema__(:embed, :profile)
    embed_schema = %Profile{id: 1}

    # Adding
    changeset = %{Changeset.change(embed_schema, name: "michal") | action: :insert}
    {:ok, changeset, _} = Relation.change(embed, changeset, nil)
    assert changeset.action == :insert

    changeset = %{changeset | action: :update}
    {:ok, changeset, _} = Relation.change(embed, changeset, nil)
    assert changeset.action == :update

    changeset = %{changeset | action: :delete}
    {:ok, changeset, _} = Relation.change(embed, changeset, nil)
    assert changeset.action == :delete

    # Replacing
    changeset = %{changeset | action: :insert}
    assert_raise RuntimeError, ~r/cannot insert related/, fn ->
      Relation.change(embed, changeset, embed_schema)
    end

    changeset = %{changeset | action: :update}
    {:ok, changeset, _} = Relation.change(embed, changeset, embed_schema)
    assert changeset.action == :update

    changeset = %{changeset | action: :delete}
    {:ok, changeset, _} = Relation.change(embed, changeset, embed_schema)
    assert changeset.action == :delete
  end

  test "change embeds_one with on_replace: :raise" do
    embed_schema = %Profile{id: 1}
    base_changeset = Changeset.change(%Author{raise_profile: embed_schema})

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_embed(base_changeset, :raise_profile, nil)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_embed(base_changeset, :raise_profile, %Profile{id: 2})
    end
  end

  test "change embeds_one with on_replace: :mark_as_invalid" do
    embed_schema = %Profile{id: 1}
    base_changeset = Changeset.change(%Author{invalid_profile: embed_schema})

    changeset = Changeset.put_embed(base_changeset, :invalid_profile, nil)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: {"is invalid", [type: :map]}]
    refute changeset.valid?

    changeset = Changeset.put_embed(base_changeset, :invalid_profile, %Profile{id: 2})
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: {"is invalid", [type: :map]}]
    refute changeset.valid?
  end

  test "change embeds_many" do
    embed = Author.__schema__(:embed, :posts)
    assert {:ok, [], true} = Relation.change(embed, [], [])

    assert {:ok, [old_changeset, new_changeset], true} =
      Relation.change(embed, [%Post{id: 1}], [%Post{id: 2}])
    assert old_changeset.action == :replace
    assert new_changeset.action == :insert

    embed_schema_changeset = Changeset.change(%Post{}, title: "hello")
    assert {:ok, [changeset], true} =
      Relation.change(embed, [embed_schema_changeset], [])
    assert changeset.action == :insert
    assert changeset.changes == %{title: "hello"}

    embed_schema = %Post{id: 1}
    embed_schema_changeset = Changeset.change(embed_schema, title: "hello")
    assert {:ok, [changeset], true} =
      Relation.change(embed, [embed_schema_changeset], [embed_schema])
    assert changeset.action == :update
    assert changeset.changes == %{title: "hello"}

    assert {:ok, [changeset], true} =
      Relation.change(embed, [], [embed_schema_changeset])
    assert changeset.action == :replace

    embed_schemas = [%Post{id: 1}, %Post{id: 2}]
    assert {:ok, [changeset1, changeset2], true} =
      Relation.change(embed, Enum.reverse(embed_schemas), embed_schemas)
    assert changeset1.action == :update
    assert changeset2.action == :update

    assert :ignore =
      Relation.change(embed, [%{embed_schema_changeset | action: :ignore}], [embed_schema])
    assert :ignore =
      Relation.change(embed, [%{embed_schema_changeset | action: :ignore}], [])

    empty_changeset = Changeset.change(embed_schema)
    assert :ignore = Relation.change(embed, [empty_changeset], [embed_schema])
  end

  test "change embeds_many with attributes" do
    assoc = Author.__schema__(:embed, :posts)

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

  test "change embeds_many with structs" do
    embed = Author.__schema__(:embed, :posts)
    post = %Post{title: "hello"}

    assert {:ok, [changeset], true} =
      Relation.change(embed, [post], [])
    assert changeset.action == :insert

    assert {:ok, [changeset], true} =
      Relation.change(embed, [Ecto.put_meta(post, state: :loaded)], [])
    assert changeset.action == :update

    assert {:ok, [changeset], true} =
      Relation.change(embed, [Ecto.put_meta(post, state: :deleted)], [])
    assert changeset.action == :delete
  end

  test "change embeds_many with on_replace: :raise" do
    embed_schema = %Post{id: 1}
    base_changeset = Changeset.change(%Author{raise_posts: [embed_schema]})

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_embed(base_changeset, :raise_posts, [])
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_embed(base_changeset, :raise_posts, [%Post{id: 2}])
    end
  end

  test "change embeds_many with on_replace: :mark_as_invalid" do
    embed_schema = %Post{id: 1}
    base_changeset = Changeset.change(%Author{invalid_posts: [embed_schema]})

    changeset = Changeset.put_embed(base_changeset, :invalid_posts, [])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"is invalid", [type: {:array, :map}]}]
    refute changeset.valid?

    changeset = Changeset.put_embed(base_changeset, :invalid_posts, [%Post{id: 2}])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"is invalid", [type: {:array, :map}]}]
    refute changeset.valid?
  end

  test "put_embed/4 insert with embeds_one" do
    base_changeset = Changeset.change(%Author{})

    changeset = Changeset.put_embed(base_changeset, :profile, %Profile{name: "michal"})
    assert %Ecto.Changeset{} = changeset.changes.profile
    assert changeset.changes.profile.action == :insert

    changeset = Changeset.put_embed(base_changeset, :profile, Changeset.change(%Profile{name: "michal"}))
    assert %Ecto.Changeset{} = changeset.changes.profile
    assert changeset.changes.profile.action == :insert

    changeset = Changeset.put_embed(base_changeset, :profile, %{name: "michal"})
    assert %Ecto.Changeset{} = changeset.changes.profile
    assert changeset.changes.profile.action == :insert

    changeset = Changeset.put_embed(base_changeset, :profile, name: "michal")
    assert %Ecto.Changeset{} = changeset.changes.profile
    assert changeset.changes.profile.action == :insert
  end

  test "put_embed/4 update with embeds_one" do
    base_changeset = Changeset.change(%Author{profile: %Profile{id: 1, name: "michal"}})

    update_changeset = Changeset.change(%Profile{id: 1, name: "michal"}, %{name: "tom"})
    changeset = Changeset.put_embed(base_changeset, :profile, update_changeset)
    assert %Ecto.Changeset{} = changeset.changes.profile
    assert changeset.changes.profile.action == :update

    changeset = Changeset.put_embed(base_changeset, :profile, %{id: 1, name: "tom"})
    assert %Ecto.Changeset{} = changeset.changes.profile
    assert changeset.changes.profile.action == :update

    changeset = Changeset.put_embed(base_changeset, :profile, id: 1, name: "tom")
    assert %Ecto.Changeset{} = changeset.changes.profile
    assert changeset.changes.profile.action == :update

    changeset = Changeset.put_embed(base_changeset, :profile, %Profile{id: 1, name: "tom"})
    refute Map.has_key?(changeset.changes, :profile)

    changeset = Changeset.put_embed(base_changeset, :profile, %Profile{id: 1, name: "michal"})
    refute Map.has_key?(changeset.changes, :profile)
  end

  test "put_embed/4 with embeds_one and empty" do
    changeset =
      %Author{}
      |> Changeset.change()
      |> Changeset.put_embed(:profile, nil)

    refute Map.has_key?(changeset.changes, :profile)

    changeset =
      %Author{profile: nil}
      |> Changeset.change()
      |> Changeset.put_embed(:profile, nil)

    refute Map.has_key?(changeset.changes, :profile)

    changeset =
      %Author{profile: %Profile{}}
      |> Changeset.change()
      |> Changeset.put_embed(:profile, nil)

    assert Map.has_key?(changeset.changes, :profile)
    assert changeset.changes[:profile] == nil

    changeset =
      %Author{}
      |> Changeset.change(profile: %Profile{})
      |> Changeset.put_embed(:profile, nil)

    refute Map.has_key?(changeset.changes, :profile)
  end

  test "put_change/4 with embeds one" do
    changeset = Changeset.change(%Author{}, profile: %Profile{name: "michal"})
    assert %Ecto.Changeset{} = changeset.changes.profile

    base_changeset = Changeset.change(%Author{profile: %Profile{name: "michal"}})
    empty_update_changeset = Changeset.change(%Profile{name: "michal"})

    changeset = Changeset.put_change(base_changeset, :profile, empty_update_changeset)
    refute Map.has_key?(changeset.changes, :profile)
  end

  test "put_change/4 with nested embed" do
    changeset =
      Changeset.change(%Author{}, %{})
      |> Changeset.put_change(:nested, %Nested{profile: %Profile{name: "tom"}})

    assert {:ok, author} = TestRepo.insert(changeset)
    assert author.nested.id
    assert author.nested.profile.id
  end

  test "put_embed/4 with embeds_many" do
    base_changeset = Changeset.change(%Author{})

    changeset = Changeset.put_embed(base_changeset, :posts, [%{title: "hello"}])
    assert [%Ecto.Changeset{}] = changeset.changes.posts
    assert hd(changeset.changes.posts).action == :insert

    changeset = Changeset.put_embed(base_changeset, :posts, [[title: "hello"]])
    assert [%Ecto.Changeset{}] = changeset.changes.posts
    assert hd(changeset.changes.posts).action == :insert

    changeset = Changeset.put_embed(base_changeset, :posts, [%Post{title: "hello"}])
    assert [%Ecto.Changeset{}] = changeset.changes.posts
    assert hd(changeset.changes.posts).action == :insert

    base_changeset = Changeset.change(%Author{posts: [%Post{title: "hello"}]})
    empty_update_changeset = Changeset.change(%Post{title: "hello"})

    changeset = Changeset.put_embed(base_changeset, :posts, [empty_update_changeset])
    refute Map.has_key?(changeset.changes, :posts)
  end

  test "put_embed/4 with embeds_many and empty" do
    changeset =
      %Author{posts: []}
      |> Changeset.change()
      |> Changeset.put_embed(:posts, [])

    refute Map.has_key?(changeset.changes, :posts)
  end

  test "put_change/3 with embeds_many" do
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

  test "get_field/3, fetch_field/2 with embeds" do
    profile_changeset = Changeset.change(%Profile{}, name: "michal")
    profile = Changeset.apply_changes(profile_changeset)

    changeset =
      %Author{}
      |> Changeset.change
      |> Changeset.put_embed(:profile, profile_changeset)
    assert Changeset.get_field(changeset, :profile) == profile
    assert Changeset.fetch_field(changeset, :profile) == {:changes, profile}

    changeset = Changeset.change(%Author{profile: profile})
    assert Changeset.get_field(changeset, :profile) == profile
    assert Changeset.fetch_field(changeset, :profile) == {:data, profile}

    post = %Post{id: 1}
    post_changeset = %{Changeset.change(post) | action: :delete}
    changeset =
      %Author{posts: [post]}
      |> Changeset.change
      |> Changeset.put_embed(:posts, [post_changeset])
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
    schema = Relation.apply_changes(embed, changeset)
    assert schema == %Profile{name: "michal"}

    changeset = Changeset.change(%Post{}, title: "hello")
    changeset2 = %{changeset | action: :delete}
    assert Relation.apply_changes(embed, changeset2) == nil

    embed = Author.__schema__(:embed, :posts)
    [schema] = Relation.apply_changes(embed, [changeset, changeset2])
    assert schema == %Post{title: "hello"}
  end

  ## traverse_errors

  test "traverses changeset errors with embeds_one error" do
    params = %{"name" => "hi", "profile" => %{"name" => "hi"}}
    changeset =
      %Author{}
      |> Changeset.cast(params, ~w(name)a)
      |> Changeset.cast_embed(:profile)
      |> Changeset.add_error(:name, "is invalid")

    errors = Changeset.traverse_errors(changeset, fn {msg, opts} ->
      msg
      |> String.replace("%{count}", to_string(opts[:count]))
      |> String.upcase()
    end)

    assert errors == %{
      profile: %{name: ["SHOULD BE AT LEAST 3 CHARACTER(S)"]},
      name: ["IS INVALID"]
    }
  end

  test "traverses changeset errors with embeds_many errors" do
    params = %{"name" => "hi", "posts" => [%{"title" => "hi"},
                                           %{"title" => "valid"}]}
    changeset =
      %Author{}
      |> Changeset.cast(params, ~w(name)a)
      |> Changeset.cast_embed(:posts)
      |> Changeset.add_error(:name, "is invalid")

    errors = Changeset.traverse_errors(changeset, fn {msg, opts} ->
      msg
      |> String.replace("%{count}", to_string(opts[:count]))
      |> String.upcase()
    end)

    assert errors == %{
      posts: [%{title: ["SHOULD BE AT LEAST 3 CHARACTER(S)"]}, %{}],
      name: ["IS INVALID"]
    }
  end

  test "traverses changeset errors with embeds_many when required" do
    changeset = cast(%Author{posts: []}, %{}, :posts, required: true)
    assert changeset.errors == [posts: {"can't be blank", [validation: :required]}]
    assert Changeset.traverse_errors(changeset, &(&1)) == %{posts: [{"can't be blank", [validation: :required]}]}

    changeset = cast(%Author{}, %{"posts" => []}, :posts, required: true)
    assert changeset.errors == [posts: {"can't be blank", [validation: :required]}]
    assert Changeset.traverse_errors(changeset, &(&1)) == %{posts: [{"can't be blank", [validation: :required]}]}

    changeset = cast(%Author{posts: []}, %{"posts" => nil}, :posts, required: true)
    assert changeset.errors == [posts: {"is invalid", [validation: :embed, type: {:array, :map}]}]
    assert Changeset.traverse_errors(changeset, &(&1)) == %{posts: [{"is invalid", [validation: :embed, type: {:array, :map}]}]}

    changeset = cast(%Author{posts: []}, %{"posts" => [%{title: nil}]}, :posts, required: true)
    assert changeset.errors == []
    assert Changeset.traverse_errors(changeset, &(&1)) == %{posts: [%{title: [{"can't be blank", [validation: :required]}]}]}
  end

  ## traverse_validations

  test "traverses changeset validations with embeds_one" do
    changeset = cast(%Author{}, %{profile: %{}}, :profile)
    assert Changeset.traverse_validations(changeset, &(&1)) == %{profile: %{name: [length: [min: 3]]}}
  end

  test "traverses changeset validations with embeds_many" do
    changeset = cast(%Author{}, %{posts: [%{}]}, :posts)
    assert Changeset.traverse_validations(changeset, &(&1)) == %{posts: [%{title: [length: [min: 3]]}]}
  end
end
