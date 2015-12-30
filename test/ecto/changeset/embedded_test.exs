defmodule Ecto.Changeset.EmbeddedTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Ecto.Changeset.Relation
  alias Ecto.Embedded

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
      embeds_many :posts, Post, on_replace: :delete
      embeds_many :raise_posts, Post, on_replace: :raise
      embeds_many :invalid_posts, Post, on_replace: :mark_as_invalid
    end
  end

  defmodule Post do
    use Ecto.Schema
    import Ecto.Changeset

    schema "posts" do
      field :title, :string
    end

    def changeset(model, params) do
      Changeset.cast(model, params, ~w(title), [])
      |> validate_length(:title, min: 3)
    end

    def optional_changeset(model, params) do
      Changeset.cast(model, params, ~w(), ~w(title))
    end

    def set_action(model, params) do
      Changeset.cast(model, params, ~w(title), [])
      |> Map.put(:action, :update)
    end
  end

  defmodule Profile do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :name
    end

    def changeset(model, params) do
      Changeset.cast(model, params, ~w(name), ~w(id))
      |> validate_length(:name, min: 3)
    end

    def optional_changeset(model, params) do
      Changeset.cast(model, params, ~w(), ~w(name))
    end

    def set_action(model, params) do
      Changeset.cast(model, params, ~w(name), ~w(id))
      |> Map.put(:action, :update)
    end
  end

  defp cast(model, params, embed, opts \\ []) do
    model
    |> Changeset.cast(params, ~w(), ~w())
    |> Changeset.cast_embed(embed, opts)
  end

  test "raises when an association is defined in embedded_schema" do
    assert_raise RuntimeError, ~r/association can't be defined in embedded_schema/, fn ->
      defmodule EmbeddedProfile do
        use Ecto.Schema

        embedded_schema do
          belongs_to :author, Author
        end
      end
    end
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
    assert changeset.changes.profile.errors  == [name: "can't be blank"]
    assert changeset.changes.profile.action  == :insert
    refute changeset.changes.profile.valid?
    refute changeset.valid?

    changeset = cast(%Author{}, %{"profile" => "value"}, :profile, required: true)
    assert changeset.errors == [profile: "is invalid"]
    refute changeset.valid?
  end

  test "cast embeds_one with existing model updating" do
    changeset = cast(%Author{profile: %Profile{name: "michal", id: "michal"}},
                     %{"profile" => %{"name" => "new", "id" => "michal"}}, :profile)

    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.action  == :update
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast embeds_one with existing model replacing" do
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

  test "cast embeds_one when required" do
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

  test "cast embeds_one with optional" do
    changeset = cast(%Author{profile: %Profile{id: "id"}}, %{"profile" => nil}, :profile)
    assert changeset.changes.profile == nil
    assert changeset.valid?
  end

  test "cast embeds_one with custom changeset" do
    changeset = cast(%Author{}, %{"profile" => %{"name" => "michal"}}, :profile,
                     with: &Profile.optional_changeset/2)
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

  test "cast embeds_one with :empty parameters" do
    changeset = cast(%Author{profile: nil}, :empty, :profile)
    assert changeset.changes == %{}

    changeset = cast(%Author{profile: %Profile{}}, :empty, :profile)
    assert changeset.changes == %{}
  end

  test "cast embeds_one with on_replace: :raise" do
    model  = %Author{raise_profile: %Profile{id: 1}}
    params = %{"raise_profile" => %{"name" => "jose", "id" => 1}}

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

  test "cast embeds_one with on_replace: :mark_as_invalid" do
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

  ## cast embeds many

  test "cast embeds_many with only new models" do
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
  test "cast embeds_many changing models" do
    posts = [%Post{title: "first",   id: 1},
             %Post{title: "second", id: 2},
             %Post{title: "third",   id: 3}]
    params = [%{"title" => "new"},
              %{"id" => "2", "title" => nil},
              %{"id" => "3", "title" => "new name"}]

    changeset = cast(%Author{posts: posts}, %{"posts" => params}, :posts)
    [first, new, second, third] = changeset.changes.posts

    assert first.model.id == 1
    assert first.required == [] # Check for not running chgangeset function
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

  test "cast embeds_many with invalid operation" do
    params = %{"posts" => [%{"id" => 1, "title" => "new"}]}
    assert_raise RuntimeError, ~r"cannot update related", fn ->
      cast(%Author{posts: []}, params, :posts, with: &Post.set_action/2)
    end
  end

  test "cast embeds_many with invalid params" do
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

  test "cast embeds_many without changes skips" do
    changeset = cast(%Author{posts: [%Post{title: "hello", id: 1}]},
                     %{"posts" => [%{"id" => 1}]}, :posts)

    refute Map.has_key?(changeset.changes, :posts)
  end

  test "cast embeds_many when required" do
    changeset = cast(%Author{posts: []}, %{}, :posts, required: true)
    assert changeset.required == [:posts]
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "can't be blank"]

    changeset = cast(%Author{posts: []}, %{"posts" => nil}, :posts, required: true)
    assert changeset.changes == %{}
    assert changeset.errors == [posts: "is invalid"]
  end

  test "cast embeds_many with :empty parameters" do
    changeset = cast(%Author{posts: []}, :empty, :posts)
    assert changeset.changes == %{}

    changeset = cast(%Author{posts: [%Post{}]}, :empty, :posts)
    assert changeset.changes == %{}
  end

  test "cast embeds_many with on_replace: :raise" do
    model = %Author{raise_posts: [%Post{id: 1}]}
    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(model, %{"raise_posts" => []}, :raise_posts)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      cast(model, %{"raise_posts" => [%{"id" => 2}]}, :raise_posts)
    end
  end

  test "cast embeds_many with on_replace: :mark_as_invalid" do
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

  ## Others

  test "change embeds_one" do
    embed = Author.__schema__(:embed, :profile)

    assert {:ok, nil, true, false} =
      Relation.change(embed, nil, %Profile{})
    assert {:ok, nil, true, true} =
      Relation.change(embed, nil, nil)

    embed_model = %Profile{}
    embed_model_changeset = Changeset.change(embed_model, name: "michal")

    assert {:ok, changeset, true, false} =
      Relation.change(embed, embed_model_changeset, nil)
    assert changeset.action == :insert
    assert changeset.changes == %{name: "michal"}

    assert {:ok, changeset, true, false} =
      Relation.change(embed, embed_model_changeset, embed_model)
    assert changeset.action == :update
    assert changeset.changes == %{name: "michal"}

    empty_changeset = Changeset.change(embed_model)
    assert {:ok, _, true, true} =
      Relation.change(embed, empty_changeset, embed_model)

    embed_with_id = %Profile{id: 2}
    assert {:ok, _, true, false} =
      Relation.change(embed, %Profile{id: 1}, embed_with_id)
  end

  test "change embeds_one with structs" do
    embed = Author.__schema__(:embed, :profile)
    profile = %Profile{name: "michal"}

    assert {:ok, changeset, true, false} =
      Relation.change(embed, profile, nil)
    assert changeset.action == :insert

    assert {:ok, changeset, true, false} =
      Relation.change(embed, Ecto.put_meta(profile, state: :loaded), nil)
    assert changeset.action == :update

    assert {:ok, changeset, true, false} =
      Relation.change(embed, Ecto.put_meta(profile, state: :deleted), nil)
    assert changeset.action == :delete
  end

  test "change embeds_one keeps appropriate action from changeset" do
    embed = Author.__schema__(:embed, :profile)
    embed_model = %Profile{}

    # Adding
    changeset = %{Changeset.change(embed_model, name: "michal") | action: :insert}
    {:ok, changeset, _, _} = Relation.change(embed, changeset, nil)
    assert changeset.action == :insert

    changeset = %{changeset | action: :update}
    {:ok, changeset, _, _} = Relation.change(embed, changeset, nil)
    assert changeset.action == :update

    changeset = %{changeset | action: :delete}
    {:ok, changeset, _, _} = Relation.change(embed, changeset, nil)
    assert changeset.action == :delete

    # Replacing
    changeset = %{changeset | action: :insert}
    assert_raise RuntimeError, ~r/cannot insert related/, fn ->
      Relation.change(embed, changeset, embed_model)
    end

    changeset = %{changeset | action: :update}
    {:ok, changeset, _, _} = Relation.change(embed, changeset, embed_model)
    assert changeset.action == :update

    changeset = %{changeset | action: :delete}
    {:ok, changeset, _, _} = Relation.change(embed, changeset, embed_model)
    assert changeset.action == :delete
  end

  test "change embeds_one with on_replace: :raise" do
    embed_model = %Profile{id: 1}
    base_changeset = Changeset.change(%Author{raise_profile: embed_model})

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_embed(base_changeset, :raise_profile, nil)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_embed(base_changeset, :raise_profile, %Profile{id: 2})
    end
  end

  test "change embeds_one with on_replace: :mark_as_invalid" do
    embed_model = %Profile{id: 1}
    base_changeset = Changeset.change(%Author{invalid_profile: embed_model})

    changeset = Changeset.put_embed(base_changeset, :invalid_profile, nil)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.put_embed(base_changeset, :invalid_profile, %Profile{id: 2})
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: "is invalid"]
    refute changeset.valid?
  end

  test "change embeds_many" do
    embed = Author.__schema__(:embed, :posts)

    assert {:ok, [old_changeset, new_changeset], true, false} =
      Relation.change(embed, [%Post{id: 1}], [%Post{id: 2}])
    assert old_changeset.action == :replace
    assert new_changeset.action == :insert

    embed_model_changeset = Changeset.change(%Post{}, title: "hello")
    assert {:ok, [changeset], true, false} =
      Relation.change(embed, [embed_model_changeset], [])
    assert changeset.action == :insert
    assert changeset.changes == %{title: "hello"}

    embed_model = %Post{id: 1}
    embed_model_changeset = Changeset.change(embed_model, title: "hello")
    assert {:ok, [changeset], true, false} =
      Relation.change(embed, [embed_model_changeset], [embed_model])
    assert changeset.action == :update
    assert changeset.changes == %{title: "hello"}

    assert {:ok, [changeset], true, false} =
      Relation.change(embed, [], [embed_model_changeset])
    assert changeset.action == :replace

    empty_changeset = Changeset.change(embed_model)
    assert {:ok, _, true, true} =
      Relation.change(embed, [empty_changeset], [embed_model])
  end

  test "change embeds_many with structs" do
    embed = Author.__schema__(:embed, :posts)
    post = %Post{title: "hello"}

    assert {:ok, [changeset], true, false} =
      Relation.change(embed, [post], [])
    assert changeset.action == :insert

    assert {:ok, [changeset], true, false} =
      Relation.change(embed, [Ecto.put_meta(post, state: :loaded)], [])
    assert changeset.action == :update

    assert {:ok, [changeset], true, false} =
      Relation.change(embed, [Ecto.put_meta(post, state: :deleted)], [])
    assert changeset.action == :delete
  end

  test "change embeds_many with on_replace: :raise" do
    embed_model = %Post{id: 1}
    base_changeset = Changeset.change(%Author{raise_posts: [embed_model]})

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_embed(base_changeset, :raise_posts, [])
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_embed(base_changeset, :raise_posts, [%Post{id: 2}])
    end
  end

  test "change embeds_many with on_replace: :mark_as_invalid" do
    embed_model = %Post{id: 1}
    base_changeset = Changeset.change(%Author{invalid_posts: [embed_model]})

    changeset = Changeset.put_embed(base_changeset, :invalid_posts, [])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.put_embed(base_changeset, :invalid_posts, [%Post{id: 2}])
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_posts: "is invalid"]
    refute changeset.valid?
  end

  test "put_embed/4" do
    base_changeset = Changeset.change(%Author{})

    changeset = Changeset.put_embed(base_changeset, :profile, %Profile{name: "michal"})
    assert %Ecto.Changeset{} = changeset.changes.profile

    base_changeset = Changeset.change(%Author{profile: %Profile{name: "michal"}})
    empty_update_changeset = Changeset.change(%Profile{name: "michal"})

    changeset = Changeset.put_embed(base_changeset, :profile, empty_update_changeset)
    refute Map.has_key?(changeset.changes, :profile)
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
    assert Changeset.fetch_field(changeset, :profile) == {:model, profile}

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
    model = Relation.apply_changes(embed, changeset)
    assert model == %Profile{name: "michal"}

    changeset = Changeset.change(%Post{}, title: "hello")
    changeset2 = %{changeset | action: :delete}
    assert Relation.apply_changes(embed, changeset2) == nil

    embed = Author.__schema__(:embed, :posts)
    [model] = Relation.apply_changes(embed, [changeset, changeset2])
    assert model == %Post{title: "hello"}
  end

  ## traverse_errors

  test "traverses changeset errors with embeds_one error" do
    params = %{"name" => "hi", "profile" => %{"name" => "hi"}}
    changeset =
      %Author{}
      |> Changeset.cast(params, ~w(), ~w(name))
      |> Changeset.cast_embed(:profile)
      |> Changeset.add_error(:name, "is invalid")

    errors = Changeset.traverse_errors(changeset, fn
      {err, opts} ->
        err
        |> String.replace("%{count}", to_string(opts[:count]))
        |> String.upcase()
      err ->
        String.upcase(err)
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
      |> Changeset.cast(params, ~w(), ~w(name))
      |> Changeset.cast_embed(:posts)
      |> Changeset.add_error(:name, "is invalid")

    errors = Changeset.traverse_errors(changeset, fn
      {err, opts} ->
        err
        |> String.replace("%{count}", to_string(opts[:count]))
        |> String.upcase()
      err ->
        String.upcase(err)
    end)

    assert errors == %{
      posts: [%{title: ["SHOULD BE AT LEAST 3 CHARACTER(S)"]}, %{}],
      name: ["IS INVALID"]
    }
  end
end
