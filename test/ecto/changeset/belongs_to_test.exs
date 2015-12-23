defmodule Ecto.Changeset.BelongsToTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Ecto.Changeset.Relation

  alias __MODULE__.Author
  alias __MODULE__.Profile

  defmodule Author do
    use Ecto.Schema

    schema "authors" do
      field :title, :string
      belongs_to :profile, {"authors_profiles", Profile},
        on_replace: :delete, defaults: [name: "default"]
      belongs_to :raise_profile, Profile, on_replace: :raise
      belongs_to :invalid_profile, Profile, on_replace: :mark_as_invalid
    end
  end

  defmodule Profile do
    use Ecto.Schema

    schema "profiles" do
      field :name
      has_one :author, Author
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

  ## cast belongs_to

  test "cast belongs_to with valid params" do
    changeset = cast(%Author{}, %{"profile" => %{"name" => "michal"}}, :profile)
    profile = changeset.changes.profile
    assert profile.changes == %{name: "michal"}
    assert profile.errors == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast belongs_to with invalid params" do
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

  test "cast belongs_to with existing model updating" do
    changeset = cast(%Author{profile: %Profile{name: "michal", id: 1}},
                     %{"profile" => %{"name" => "new", "id" => 1}}, :profile)

    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.action  == :update
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast belongs_to without loading" do
    assert cast(%Author{}, %{"profile" => nil}, :profile).changes == %{}

    loaded = put_in %Author{}.__meta__.state, :loaded
    assert_raise RuntimeError, ~r"attempting to cast or change association `profile` .* that was not loaded", fn ->
      cast(loaded, %{"profile" => nil}, :profile)
    end
  end

  test "cast belongs_to with existing model replacing" do
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

  test "cast belongs_to without changes skips" do
    changeset = cast(%Author{profile: %Profile{name: "michal", id: 1}},
                     %{"profile" => %{"id" => 1}}, :profile)
    assert changeset.changes == %{}
    assert changeset.errors == []

    changeset = cast(%Author{profile: %Profile{name: "michal", id: 1}},
                     %{"profile" => %{"id" => "1"}}, :profile)
    assert changeset.changes == %{}
    assert changeset.errors == []
  end

  test "cast belongs_to when required" do
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

  test "cast belongs_to with optional" do
    changeset = cast(%Author{profile: %Profile{id: "id"}}, %{"profile" => nil}, :profile)
    assert changeset.changes.profile == nil
    assert changeset.valid?
  end

  test "cast belongs_to with custom changeset" do
    changeset = cast(%Author{}, %{"profile" => %{}}, :profile, with: &Profile.optional_changeset/2)
    profile = changeset.changes.profile
    assert profile.model.name == "default"
    assert profile.model.__meta__.source == {nil, "authors_profiles"}
    assert profile.changes == %{}
    assert profile.errors  == []
    assert profile.action  == :insert
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast belongs_to keeps appropriate action from changeset" do
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

  test "cast belongs_to with :empty parameters" do
    changeset = cast(%Author{profile: nil}, :empty, :profile)
    assert changeset.changes == %{}

    changeset = cast(%Author{}, :empty, :profile, required: true)
    assert changeset.changes == %{}

    changeset = cast(%Author{profile: %Profile{}}, :empty, :profile, required: true)
    assert changeset.changes == %{}
  end

  test "cast belongs_to with on_replace: :raise" do
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

  test "cast belongs_to with on_replace: :mark_as_invalid" do
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

  test "cast belongs_to twice" do
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

  ## Change

  test "change belongs_to" do
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

  test "change belongs_to with struct" do
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

  test "change belongs_to keeps appropriate action from changeset" do
    assoc = Author.__schema__(:association, :profile)
    assoc_model = %Profile{}

    # Adding
    changeset = %{Changeset.change(assoc_model, name: "michal") | action: :insert}
    {:ok, changeset, _, _} = Relation.change(assoc, changeset, nil)
    assert changeset.action == :insert

    changeset = %{changeset | action: :update}
    {:ok, changeset, _, _} = Relation.change(assoc, changeset, nil)
    assert changeset.action == :update

    changeset = %{changeset | action: :delete}
    {:ok, changeset, _, _} = Relation.change(assoc, changeset, nil)
    assert changeset.action == :delete

    # Replacing
    changeset = %{Changeset.change(assoc_model, name: "michal") | action: :insert}
    assert_raise RuntimeError, ~r/cannot insert related/, fn ->
      Relation.change(assoc, changeset, assoc_model)
    end

    changeset = %{changeset | action: :update}
    {:ok, changeset, _, _} = Relation.change(assoc, changeset, assoc_model)
    assert changeset.action == :update

    changeset = %{changeset | action: :delete}
    {:ok, changeset, _, _} = Relation.change(assoc, changeset, assoc_model)
    assert changeset.action == :delete
  end

  test "change belongs_to with on_replace: :raise" do
    assoc_model = %Profile{id: 1}
    base_changeset = Changeset.change(%Author{raise_profile: assoc_model})

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :raise_profile, nil)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :raise_profile, %Profile{id: 2})
    end
  end

  test "change belongs_to with on_replace: :mark_as_invalid" do
    assoc_model = %Profile{id: 1}
    base_changeset = Changeset.change(%Author{invalid_profile: assoc_model})

    changeset = Changeset.put_assoc(base_changeset, :invalid_profile, nil)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: "is invalid"]
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
  end

  test "on_replace: :nilify" do
    # one case is handled inside repo
    profile = %Profile{id: 1}
    changeset = cast(%Author{profile: profile}, %{"profile" => nil}, :profile)
    assert changeset.changes.profile == nil
  end

  test "apply_changes" do
    embed = Author.__schema__(:association, :profile)

    changeset = Changeset.change(%Profile{}, name: "michal")
    assert Relation.apply_changes(embed, changeset) == %Profile{name: "michal"}

    changeset = Changeset.change(%Profile{}, title: "hello")
    changeset2 = %{changeset | action: :delete}
    assert Relation.apply_changes(embed, changeset2) == nil
  end
end
