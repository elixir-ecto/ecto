defmodule Ecto.Changeset.EmbeddedNoPkTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Ecto.Changeset.Relation
  alias Ecto.TestRepo

  alias __MODULE__.Author
  alias __MODULE__.Profile
  alias __MODULE__.Post

  defmodule Author do
    use Ecto.Schema

    schema "authors" do
      field :name, :string
      embeds_one :profile, Profile, on_replace: :delete
      embeds_one :raise_profile, Profile, on_replace: :raise
      embeds_one :invalid_profile, Profile, on_replace: :mark_as_invalid
      embeds_one :update_profile, Profile, on_replace: :update
      embeds_many :posts, Post, on_replace: :delete
      embeds_many :raise_posts, Post, on_replace: :raise
      embeds_many :invalid_posts, Post, on_replace: :mark_as_invalid
    end
  end

  defmodule Post do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
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
      |> Map.put(:action, :update)
    end
  end

  defmodule Profile do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :name
    end

    def changeset(schema, params) do
      cast(schema, params, ~w(name)a)
      |> validate_required(:name)
      |> validate_length(:name, min: 3)
    end

    def optional_changeset(schema, params) do
      cast(schema, params, ~w(name)a)
    end

    def set_action(schema, params) do
      changeset(schema, params)
      |> Map.put(:action, :update)
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

    changeset = cast(%Author{}, %{"profile" => "value"}, :profile, required: true)
    assert changeset.errors == [profile: {"is invalid", [validation: :embed, type: :map]}]
    refute changeset.valid?
  end

  test "cast embeds_one replacing" do
    changeset = cast(%Author{profile: %Profile{name: "michal"}},
                     %{"profile" => %{"name" => "new"}}, :profile)
    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?

    changeset = cast(%Author{profile: %Profile{name: "michal"}},
                     %{"profile" => %{name: "michal"}}, :profile)
    profile = changeset.changes.profile
    assert profile.changes == %{name: "michal"}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?

    assert_raise RuntimeError, ~r"cannot update related", fn ->
      cast(%Author{profile: %Profile{name: "michal"}},
           %{"profile" => %{"name" => "new"}},
           :profile, with: &Profile.set_action/2)
    end
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
    changeset = cast(%Author{profile: %Profile{}}, %{"profile" => nil}, :profile)
    assert changeset.changes.profile == nil
    assert changeset.valid?
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

  test "cast embeds_one with empty parameters" do
    changeset = cast(%Author{profile: nil}, %{}, :profile)
    assert changeset.changes == %{}

    changeset = cast(%Author{profile: %Profile{}}, %{}, :profile)
    assert changeset.changes == %{}
  end

  test "cast embeds_one with on_replace: :raise" do
    schema = %Author{raise_profile: %Profile{}}

    params = %{"raise_profile" => nil}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(schema, params, :raise_profile)
    end

    params = %{"raise_profile" => %{"name" => "new"}}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(schema, params, :raise_profile)
    end
  end

  test "cast embeds_one with on_replace: :mark_as_invalid" do
    schema = %Author{invalid_profile: %Profile{}}

    changeset = cast(schema, %{"invalid_profile" => nil}, :invalid_profile)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: {"is invalid", [validation: :embed, type: :map]}]
    refute changeset.valid?

    changeset = cast(schema, %{"invalid_profile" => %{}}, :invalid_profile)
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

    changeset = cast(schema, %{"update_profile" => %{id: 2, name: "Jose"}}, :update_profile)
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

  test "cast embeds_many with map with numbered string keys" do
    changeset = cast(%Author{}, %{"posts" => %{"1" => %{"title" => "one"}, "2" => %{"title" => "two"}, "10" => %{"title" => "ten"}}}, :posts)
    [one, two, ten] = changeset.changes.posts
    assert one.changes == %{title: "one"}
    assert two.changes == %{title: "two"}
    assert ten.changes == %{title: "ten"}
    assert changeset.valid?
  end

  test "cast embeds_many with map with non-numbered keys" do
    changeset = cast(%Author{}, %{"posts" => %{"b" => %{"title" => "two"}, "a" => %{"title" => "one"}}}, :posts)
    [one, two] = changeset.changes.posts
    assert one.changes == %{title: "one"}
    assert two.changes == %{title: "two"}
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

  test "cast embeds_many with invalid operation" do
    params = %{"posts" => [%{"title" => "new"}]}
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
  end

  test "cast embeds_many replacing" do
    changeset = cast(%Author{posts: [%Post{title: "hello"}]},
                     %{"posts" => [%{}]}, :posts)
    [old_changeset, new_changeset] = changeset.changes.posts
    assert old_changeset.changes == %{}
    assert old_changeset.action == :replace
    assert new_changeset.changes == %{}
    assert new_changeset.action == :insert
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

  test "cast embeds_many with empty parameters" do
    changeset = cast(%Author{posts: []}, %{}, :posts)
    assert changeset.changes == %{}

    changeset = cast(%Author{posts: [%Post{}]}, %{}, :posts)
    assert changeset.changes == %{}
  end

  test "cast embeds_many with on_replace: :raise" do
    schema = %Author{raise_posts: [%Post{}]}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(schema, %{"raise_posts" => []}, :raise_posts)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(schema, %{"raise_posts" => [%{}]}, :raise_posts)
    end
  end

  test "cast embeds_many with on_replace: :mark_as_invalid" do
    schema = %Author{invalid_posts: [%Post{}]}

    changeset = cast(schema, %{"invalid_posts" => []}, :invalid_posts)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"is invalid", [validation: :embed, type: {:array, :map}]}]
    refute changeset.valid?

    changeset = cast(schema, %{"invalid_posts" => [%{}]}, :invalid_posts)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"is invalid", [validation: :embed, type: {:array, :map}]}]
    refute changeset.valid?
  end

  ## Others

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

    empty_changeset = Changeset.change(embed_schema)
    assert {:ok, _, true} =
      Relation.change(embed, empty_changeset, embed_schema)

    embed_with_id = %Profile{}
    assert {:ok, _, true} =
      Relation.change(embed, %Profile{}, embed_with_id)
  end

  test "change embeds_one with attributes" do
    assoc = Author.__schema__(:embed, :profile)

    assert {:ok, changeset, true} =
      Relation.change(assoc, %{name: "michal"}, nil)
    assert changeset.action == :insert
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

  test "change embeds_one with structs" do
    embed = Author.__schema__(:embed, :profile)
    profile = %Profile{name: "michal"}

    assert {:ok, changeset, true} =
      Relation.change(embed, profile, nil)
    assert changeset.action == :insert
  end

  test "change embeds_one keeps appropriate action from changeset" do
    embed = Author.__schema__(:embed, :profile)
    embed_schema = %Profile{}

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
    {:ok, changeset, _} = Relation.change(embed, changeset, embed_schema)
    assert changeset.action == :insert

    changeset = %{changeset | action: :update}
    {:ok, changeset, _} = Relation.change(embed, changeset, embed_schema)
    assert changeset.action == :update

    changeset = %{changeset | action: :delete}
    {:ok, changeset, _} = Relation.change(embed, changeset, embed_schema)
    assert changeset.action == :delete
  end

  test "change embeds_one with on_replace: :raise" do
    embed_schema = %Profile{}
    base_changeset = Changeset.change(%Author{raise_profile: embed_schema})

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_embed(base_changeset, :raise_profile, nil)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_embed(base_changeset, :raise_profile, %Profile{})
    end
  end

  test "change embeds_one with on_replace: :mark_as_invalid" do
    embed_schema = %Profile{}
    base_changeset = Changeset.change(%Author{invalid_profile: embed_schema})

    changeset = Changeset.put_embed(base_changeset, :invalid_profile, nil)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: {"is invalid", [type: :map]}]
    refute changeset.valid?

    changeset = Changeset.put_embed(base_changeset, :invalid_profile, %Profile{})
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: {"is invalid", [type: :map]}]
    refute changeset.valid?
  end

  test "change embeds_many" do
    embed = Author.__schema__(:embed, :posts)

    assert {:ok, [], true} = Relation.change(embed, [], [])

    assert {:ok, [old_changeset, new_changeset], true} =
      Relation.change(embed, [%Post{}], [%Post{}])
    assert old_changeset.action == :replace
    assert new_changeset.action == :insert

    embed_schema_changeset = Changeset.change(%Post{}, title: "hello")
    assert {:ok, [changeset], true} =
      Relation.change(embed, [embed_schema_changeset], [])
    assert changeset.action == :insert
    assert changeset.changes == %{title: "hello"}

    embed_schema = %Post{}
    embed_schema_changeset = Changeset.change(embed_schema, title: "hello")
    assert {:ok, [old_changeset, new_changeset], true} =
      Relation.change(embed, [embed_schema_changeset], [embed_schema])
    assert old_changeset.action == :replace
    assert old_changeset.changes == %{}
    assert new_changeset.action == :insert
    assert new_changeset.changes == %{title: "hello"}

    assert {:ok, [changeset], true} =
      Relation.change(embed, [], [embed_schema_changeset])
    assert changeset.action == :replace

    empty_changeset = Changeset.change(embed_schema)
    assert {:ok, _, true} =
      Relation.change(embed, [empty_changeset], [embed_schema])
  end

  test "change embeds_many with attributes" do
    assoc = Author.__schema__(:embed, :posts)

    assert {:ok, [changeset], true} =
      Relation.change(assoc, [%{title: "hello"}], [])
    assert changeset.action == :insert
    assert changeset.changes == %{title: "hello"}

    post = %Post{title: "other"} |> Ecto.put_meta(state: :loaded)
    assert {:ok, [old_changeset, new_changeset], true} =
      Relation.change(assoc, [[title: "hello"]], [post])
    assert old_changeset.action == :replace
    assert old_changeset.changes == %{}
    assert new_changeset.action == :insert
    assert new_changeset.changes == %{title: "hello"}
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
    embed_schema = %Post{}
    base_changeset = Changeset.change(%Author{raise_posts: [embed_schema]})

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_embed(base_changeset, :raise_posts, [])
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_embed(base_changeset, :raise_posts, [%Post{}])
    end
  end

  test "change embeds_many with on_replace: :mark_as_invalid" do
    embed_schema = %Post{}
    base_changeset = Changeset.change(%Author{invalid_posts: [embed_schema]})

    changeset = Changeset.put_embed(base_changeset, :invalid_posts, [])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"is invalid", [type: {:array, :map}]}]
    refute changeset.valid?

    changeset = Changeset.put_embed(base_changeset, :invalid_posts, [%Post{}])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"is invalid", [type: {:array, :map}]}]
    refute changeset.valid?
  end
end
