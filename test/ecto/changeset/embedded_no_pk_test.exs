defmodule Ecto.Changeset.EmbeddedNoPkTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Ecto.TestRepo

  alias __MODULE__.Author
  alias __MODULE__.Profile
  alias __MODULE__.Post

  defmodule Author do
    use Ecto.Schema

    schema "authors" do
      field :name, :string
      embeds_one :profile, Profile, on_replace: :delete
      field :profile_with_action, {Ecto.Type.Embed, type: Profile, with: &Profile.set_action/2, on_replace: :delete}
      field :profile_with_optional_changeset, {Ecto.Type.Embed, type: Profile, with: &Profile.optional_changeset/2, on_replace: :delete}
      embeds_one :raise_profile, Profile, on_replace: :raise
      embeds_one :invalid_profile, Profile, on_replace: :mark_as_invalid
      embeds_one :update_profile, Profile, on_replace: :update
      embeds_many :posts, Post, on_replace: :delete
      embeds_many :posts_with_action, Post, on_replace: :delete, with: &Post.set_action/2
      embeds_many :posts_with_opional_changeset, Post, on_replace: :delete, with: &Post.optional_changeset/2
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

  ## Cast embeds one

  test "cast embeds_one with valid params" do
    changeset = Changeset.cast(%Author{}, %{"profile" => %{"name" => "michal"}}, [:profile])
    profile = changeset.changes.profile
    assert profile.changes == %{name: "michal"}
    assert profile.errors == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast embeds_one with invalid params" do
    changeset = Changeset.cast(%Author{}, %{"profile" => %{}}, [:profile])
    assert changeset.changes.profile.changes == %{}
    assert changeset.changes.profile.errors  == [name: {"can't be blank", [validation: :required]}]
    assert changeset.changes.profile.action  == :insert
    refute changeset.changes.profile.valid?
    refute changeset.valid?

    changeset = Changeset.cast(%Author{}, %{"profile" => "value"}, [:profile])
    assert changeset.errors == [profile: {"is invalid", [type: Author.__schema__(:type, :profile), validation: :cast]}]
    refute changeset.valid?
  end

  @tag :skip # Need to figure out action issue
  test "cast embeds_one replacing" do
    changeset = Changeset.cast(%Author{profile: %Profile{name: "michal"}},
                     %{"profile" => %{"name" => "new"}}, [:profile])
    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?

    changeset = Changeset.cast(%Author{profile: %Profile{name: "michal"}},
                     %{"profile" => %{name: "michal"}}, [:profile])
    profile = changeset.changes.profile
    assert profile.changes == %{name: "michal"}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?

    assert_raise RuntimeError, ~r"cannot update related", fn ->
      Changeset.cast(%Author{profile_with_action: %Profile{name: "michal"}},
           %{"profile_with_action" => %{"name" => "new"}},
           :profile_with_action)
    end
  end

  @tag :skip # validate_required seems to be overwriting changeset.changes in the last block
  test "cast embeds_one when required" do
    changeset = Changeset.cast(%Author{profile: nil}, %{}, [:profile]) |> Changeset.validate_required(:profile)
    assert changeset.required == [:profile]
    assert changeset.changes == %{}
    assert changeset.errors == [profile: {"can't be blank", [validation: :required]}]

    changeset = Changeset.cast(%Author{profile: nil}, %{}, [:profile]) |> Changeset.validate_required(:profile, message: "a custom message")
    assert changeset.required == [:profile]
    assert changeset.changes == %{}
    assert changeset.errors == [profile: {"a custom message", [validation: :required]}]

    changeset = Changeset.cast(%Author{profile: %Profile{}}, %{}, [:profile]) |> Changeset.validate_required(:profile)
    assert changeset.required == [:profile]
    assert changeset.changes == %{}
    assert changeset.errors == []

    changeset = Changeset.cast(%Author{profile: nil}, %{"profile" => nil}, [:profile]) |> Changeset.validate_required(:profile)
    assert changeset.required == [:profile]
    assert changeset.changes == %{}
    assert changeset.errors == [profile: {"can't be blank", [validation: :required]}]

    changeset = Changeset.cast(%Author{profile: %Profile{}}, %{"profile" => nil}, [:profile]) |> Changeset.validate_required(:profile)
    assert changeset.required == [:profile]
    assert changeset.changes == %{profile: nil}
    assert changeset.errors == [profile: {"can't be blank", [validation: :required]}]
  end

  test "cast embeds_one with optional" do
    changeset = Changeset.cast(%Author{profile: %Profile{}}, %{"profile" => nil}, [:profile])
    assert changeset.changes.profile == nil
    assert changeset.valid?
  end

  test "cast embeds_one with custom changeset" do
    changeset = Changeset.cast(%Author{}, %{"profile_with_optional_changeset" => %{"name" => "michal"}}, [:profile_with_optional_changeset])

    # assert (changeset.types.profile |> elem(1)).on_cast == &Profile.optional_changeset/2
    profile_with_optional_changeset = changeset.changes.profile_with_optional_changeset
    assert profile_with_optional_changeset.changes == %{name: "michal"}
    assert profile_with_optional_changeset.errors  == []
    assert profile_with_optional_changeset.action  == :insert
    assert profile_with_optional_changeset.valid?
    assert changeset.valid?
  end

  test "cast embeds_one with empty parameters" do
    changeset = Changeset.cast(%Author{profile: nil}, %{}, [:profile])
    assert changeset.changes == %{}

    changeset = Changeset.cast(%Author{profile: %Profile{}}, %{}, [:profile])
    assert changeset.changes == %{}
  end

  test "cast embeds_one with on_replace: :raise" do
    schema = %Author{raise_profile: %Profile{}}

    params = %{"raise_profile" => nil}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.cast(schema, params, [:raise_profile])
    end

    params = %{"raise_profile" => %{"name" => "new"}}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.cast(schema, params, [:raise_profile])
    end
  end

  @tag :skip # Need to implement custom invalid messages
  test "cast embeds_one with on_replace: :mark_as_invalid" do
    schema = %Author{invalid_profile: %Profile{}}

    changeset = Changeset.cast(schema, %{"invalid_profile" => nil}, [:invalid_profile])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: {"is invalid", [type: Author.__schema__(:type, :invalid_profile), validation: :cast]}]
    refute changeset.valid?

    changeset = Changeset.cast(schema, %{"invalid_profile" => %{}}, [:invalid_profile])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: {"is invalid", [type: Author.__schema__(:type, :invalid_profile), validation: :cast]}]
    refute changeset.valid?

    changeset = Changeset.cast(schema, %{"invalid_profile" => nil}, [:invalid_profile], invalid_message: "a custom message")
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: {"a custom message", [type: Author.__schema__(:type, :invalid_profile), validation: :cast]}]
    refute changeset.valid?
  end

  @tag :skip # Insert fails saying invalid_posts is invalid.
  test "cast embeds_one with on_replace: :update" do
    {:ok, schema} = TestRepo.insert(%Author{name: "Enio",
      update_profile: %Profile{name: "Enio"}})

    changeset = Changeset.cast(schema, %{"update_profile" => %{id: 2, name: "Jose"}}, [:update_profile])
    assert changeset.changes.update_profile.changes == %{name: "Jose"}
    assert changeset.changes.update_profile.action == :update
    assert changeset.errors == []
    assert changeset.valid?
  end

  test "raises when :update is used on embeds_many" do
    error_message = "Invalid on_replace for tags: :update"
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
    changeset = Changeset.cast(%Author{}, %{"posts" => [%{"title" => "hello"}]}, [:posts])
    [post_change] = changeset.changes.posts
    assert post_change.changes == %{title: "hello"}
    assert post_change.errors  == []
    assert post_change.action  == :insert
    assert post_change.valid?
    assert changeset.valid?
  end

  test "cast embeds_many with map" do
    changeset = Changeset.cast(%Author{}, %{"posts" => %{0 => %{"title" => "hello"}}}, [:posts])
    [post_change] = changeset.changes.posts
    assert post_change.changes == %{title: "hello"}
    assert post_change.errors  == []
    assert post_change.action  == :insert
    assert post_change.valid?
    assert changeset.valid?
  end

  test "cast embeds_many with map with numbered string keys" do
    changeset = Changeset.cast(%Author{}, %{"posts" => %{"1" => %{"title" => "one"}, "2" => %{"title" => "two"}, "10" => %{"title" => "ten"}}}, [:posts])
    [one, two, ten] = changeset.changes.posts
    assert one.changes == %{title: "one"}
    assert two.changes == %{title: "two"}
    assert ten.changes == %{title: "ten"}
    assert changeset.valid?
  end

  test "cast embeds_many with map with non-numbered keys" do
    changeset = Changeset.cast(%Author{}, %{"posts" => %{"b" => %{"title" => "two"}, "a" => %{"title" => "one"}}}, [:posts])
    [one, two] = changeset.changes.posts
    assert one.changes == %{title: "one"}
    assert two.changes == %{title: "two"}
    assert changeset.valid?
  end

  test "cast embeds_many with custom changeset" do
    changeset = Changeset.cast(%Author{}, %{"posts_with_opional_changeset" => [%{"title" => "hello"}]},
                     [:posts_with_opional_changeset])
    [post_change] = changeset.changes.posts_with_opional_changeset
    assert post_change.changes == %{title: "hello"}
    assert post_change.errors  == []
    assert post_change.action  == :insert
    assert post_change.valid?
    assert changeset.valid?
  end

  @tag :skip # Need to figure out EmbedMany replacing
  test "cast embeds_many with invalid operation" do
    params = %{"posts_with_action" => [%{"title" => "new"}]}
    assert_raise RuntimeError, ~r"cannot update related", fn ->
      Changeset.cast(%Author{posts_with_action: []}, params, [:posts_with_action])
    end
  end

  test "cast embeds_many with invalid params" do
    changeset = Changeset.cast(%Author{}, %{"posts" => "value"}, [:posts])
    assert changeset.errors == [posts: {"is invalid", [type: Author.__schema__(:type, :posts), validation: :cast]}]
    refute changeset.valid?

    changeset = Changeset.cast(%Author{}, %{"posts" => ["value"]}, [:posts])
    assert changeset.errors == [posts: {"is invalid", [type: Author.__schema__(:type, :posts), validation: :cast]}]
    refute changeset.valid?

    changeset = Changeset.cast(%Author{}, %{"posts" => nil}, [:posts])
    assert changeset.errors == [posts: {"is invalid", [type: Author.__schema__(:type, :posts), validation: :cast]}]
    refute changeset.valid?
  end

  @tag :skip # Need to figure out EmbedMany replacing
  test "cast embeds_many replacing" do
    changeset = Changeset.cast(%Author{posts: [%Post{title: "hello"}]},
                     %{"posts" => [%{}]}, [:posts])
    [old_changeset, new_changeset] = changeset.changes.posts
    assert old_changeset.changes == %{}
    assert old_changeset.action == :replace
    assert new_changeset.changes == %{}
    assert new_changeset.action == :insert
  end

  @tag :skip # Need to figure out how to deal with multiple errors as validate_required is changed
  test "cast embeds_many when required" do
    changeset = Changeset.cast(%Author{posts: []}, %{}, [:posts]) |> Changeset.validate_required([:posts])
    assert changeset.required == [:posts]
    assert changeset.changes == %{}
    assert changeset.errors == [posts: {"can't be blank", [validation: :required]}]

    changeset = Changeset.cast(%Author{posts: []}, %{"posts" => nil}, [:posts]) |> Changeset.validate_required([:posts])
    assert changeset.changes == %{}
    assert changeset.errors == [posts: {"can't be blank", [validation: :required]}]
  end

  test "cast embeds_many with empty parameters" do
    changeset = Changeset.cast(%Author{posts: []}, %{}, [:posts])
    assert changeset.changes == %{}

    changeset = Changeset.cast(%Author{posts: [%Post{}]}, %{}, [:posts])
    assert changeset.changes == %{}
  end

  test "cast embeds_many with on_replace: :raise" do
    schema = %Author{raise_posts: [%Post{}]}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.cast(schema, %{"raise_posts" => []}, [:raise_posts])
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.cast(schema, %{"raise_posts" => [%{}]}, [:raise_posts])
    end
  end

  test "cast embeds_many with on_replace: :mark_as_invalid" do
    schema = %Author{invalid_posts: [%Post{}]}

    changeset = Changeset.cast(schema, %{"invalid_posts" => []}, [:invalid_posts])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"is invalid", [type: Author.__schema__(:type, :invalid_posts), validation: :cast]}]
    refute changeset.valid?

    changeset = Changeset.cast(schema, %{"invalid_posts" => [%{}]}, [:invalid_posts])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: {"is invalid", [type: Author.__schema__(:type, :invalid_posts), validation: :cast]}]
    refute changeset.valid?
  end

  ## Others

  test "change embeds_one" do
    {:parameterized, Ecto.Type.Embed, opts} = Author.__schema__(:type, :profile)

    assert {:ok, nil, true} = Ecto.Type.Embed.change(nil, nil, opts)
    assert {:ok, nil, true} = Ecto.Type.Embed.change(nil, %Profile{}, opts)

    embed_schema = %Profile{}
    embed_schema_changeset = Changeset.change(embed_schema, name: "michal")

    assert {:ok, changeset, true} =
      Ecto.Type.Embed.change(embed_schema_changeset, nil, opts)
    assert changeset.action == :insert
    assert changeset.changes == %{name: "michal"}

    empty_changeset = Changeset.change(embed_schema)
    assert {:ok, _, true} =
      Ecto.Type.Embed.change(empty_changeset, embed_schema, opts)

    embed_with_id = %Profile{}
    assert {:ok, _, true} =
      Ecto.Type.Embed.change(%Profile{}, embed_with_id, opts)
  end

  @tag :skip # Need to figure out why action is update insttead of insert in second assert block
  test "change embeds_one with attributes" do
    {:parameterized, Ecto.Type.Embed, opts} = Author.__schema__(:type, :profile)

    assert {:ok, changeset, true} =
      Ecto.Type.Embed.change(%{name: "michal"}, nil, opts)
    assert changeset.action == :insert
    assert changeset.changes == %{name: "michal"}

    profile = %Profile{name: "other"}

    assert {:ok, changeset, true} =
      Ecto.Type.Embed.change(%{name: "michal"}, profile, opts)
    assert changeset.action == :insert
    assert changeset.changes == %{name: "michal"}

    assert {:ok, changeset, true} =
      Ecto.Type.EmbedMany.change([name: "michal"], profile, opts)
    assert changeset.action == :insert
    assert changeset.changes == %{name: "michal"}
  end

  test "change embeds_one with structs" do
    {:parameterized, Ecto.Type.Embed, opts} = Author.__schema__(:type, :profile)
    profile = %Profile{name: "michal"}

    assert {:ok, changeset, true} =
      Ecto.Type.Embed.change(profile, nil, opts)
    assert changeset.action == :insert
  end

  test "change embeds_one keeps appropriate action from changeset" do
    {:parameterized, Ecto.Type.Embed, opts} = Author.__schema__(:type, :profile)
    embed_schema = %Profile{}

    # Adding
    changeset = %{Changeset.change(embed_schema, name: "michal") | action: :insert}
    {:ok, changeset, _} = Ecto.Type.Embed.change(changeset, nil, opts)
    assert changeset.action == :insert

    changeset = %{changeset | action: :update}
    {:ok, changeset, _} = Ecto.Type.Embed.change(changeset, nil, opts)
    assert changeset.action == :update

    changeset = %{changeset | action: :delete}
    {:ok, changeset, _} = Ecto.Type.Embed.change(changeset, nil, opts)
    assert changeset.action == :delete

    # Replacing
    changeset = %{changeset | action: :insert}
    {:ok, changeset, _} = Ecto.Type.Embed.change(changeset, embed_schema, opts)
    assert changeset.action == :insert

    changeset = %{changeset | action: :update}
    {:ok, changeset, _} = Ecto.Type.Embed.change(changeset, embed_schema, opts)
    assert changeset.action == :update

    changeset = %{changeset | action: :delete}
    {:ok, changeset, _} = Ecto.Type.Embed.change(changeset, embed_schema, opts)
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

  @tag :skip # Need to figure out how to empty changes on :mark_as_invalid
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

  @tag :skip # Need to figure out EmbedMany changing lists
  test "change embeds_many" do
    {:parameterized, Ecto.Type.EmbedMany, opts} = Author.__schema__(:type, :posts)

    assert {:ok, [], true} = Ecto.Type.EmbedMany.change([], [], opts)

    assert {:ok, [old_changeset, new_changeset], true} =
      Ecto.Type.EmbedMany.change([%Post{}], [%Post{}], opts)
    assert old_changeset.action == :replace
    assert new_changeset.action == :insert

    embed_schema_changeset = Changeset.change(%Post{}, title: "hello")
    assert {:ok, [changeset], true} =
      Ecto.Type.EmbedMany.change([embed_schema_changeset], [], opts)
    assert changeset.action == :insert
    assert changeset.changes == %{title: "hello"}

    embed_schema = %Post{}
    embed_schema_changeset = Changeset.change(embed_schema, title: "hello")
    assert {:ok, [old_changeset, new_changeset], true} =
      Ecto.Type.EmbedMany.change([embed_schema_changeset], [embed_schema], opts)
    assert old_changeset.action == :replace
    assert old_changeset.changes == %{}
    assert new_changeset.action == :insert
    assert new_changeset.changes == %{title: "hello"}

    assert {:ok, [changeset], true} =
      Ecto.Type.EmbedMany.change([], [embed_schema_changeset], opts)
    assert changeset.action == :replace

    empty_changeset = Changeset.change(embed_schema)
    assert {:ok, _, true} =
      Ecto.Type.EmbedMany.change([empty_changeset], [embed_schema], opts)
  end

  @tag :skip # Need to figure out EmbedMany changing lists
  test "change embeds_many with attributes" do
    {:parameterized, Ecto.Type.EmbedMany, opts} = Author.__schema__(:type, :posts)

    assert {:ok, [changeset], true} =
      Ecto.Type.EmbedMany.change([%{title: "hello"}], [], opts)
    assert changeset.action == :insert
    assert changeset.changes == %{title: "hello"}

    post = %Post{title: "other"} |> Ecto.put_meta(state: :loaded)
    assert {:ok, [old_changeset, new_changeset], true} =
      Ecto.Type.EmbedMany.change([[title: "hello"]], [post], opts)
    assert old_changeset.action == :replace
    assert old_changeset.changes == %{}
    assert new_changeset.action == :insert
    assert new_changeset.changes == %{title: "hello"}
  end

  @tag :skip # Need to figure out EmbedMany changing lists
  test "change embeds_many with structs" do
    {:parameterized, Ecto.Type.EmbedMany, opts} = Author.__schema__(:type, :posts)
    post = %Post{title: "hello"}

    assert {:ok, [changeset], true} =
      Ecto.Type.EmbedMany.change([post], [], opts)
    assert changeset.action == :insert

    assert {:ok, [changeset], true} =
      Ecto.Type.EmbedMany.change([Ecto.put_meta(post, state: :loaded)], [], opts)
    assert changeset.action == :update

    assert {:ok, [changeset], true} =
      Ecto.Type.EmbedMany.change([Ecto.put_meta(post, state: :deleted)], [], opts)
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
