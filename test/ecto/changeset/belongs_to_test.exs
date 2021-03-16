defmodule Ecto.Changeset.BelongsToTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Ecto.Changeset.Relation
  alias Ecto.TestRepo

  alias __MODULE__.Author
  alias __MODULE__.Profile

  defmodule Author do
    use Ecto.Schema

    schema "authors" do
      field :title, :string
      belongs_to :profile, {"authors_profiles", Profile},
        on_replace: :delete, defaults: [name: "default"]
      belongs_to :raise_profile, Profile, on_replace: :raise
      belongs_to :invalid_profile, Profile, on_replace: :mark_as_invalid, defaults: :send_to_self
      belongs_to :update_profile, Profile, on_replace: :update, defaults: {__MODULE__, :send_to_self, [:extra]}
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
      has_one :author, Author
    end

    def changeset(schema, params) do
      Changeset.cast(schema, params, ~w(name id)a)
      |> Changeset.validate_required(:name)
    end

    def optional_changeset(schema, params) do
      Changeset.cast(schema, params, ~w(name)a)
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
    assert changeset.changes.profile.errors  == [name: {"can't be blank", [validation: :required]}]
    assert changeset.changes.profile.action  == :insert
    refute changeset.changes.profile.valid?
    refute changeset.valid?

    changeset = cast(%Author{}, %{"profile" => "value"}, :profile)
    assert changeset.errors == [profile: {"is invalid", [validation: :assoc, type: :map]}]
    refute changeset.valid?
  end

  test "cast belongs_to with existing struct updating" do
    changeset = cast(%Author{profile: %Profile{name: "michal", id: 1}},
                     %{"profile" => %{"name" => "new", "id" => 1}}, :profile)

    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.action  == :update
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast belongs_to with empty value" do
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

  test "cast belongs_to discards changesets marked as ignore" do
    changeset = cast(%Author{},
                     %{"profile" => %{name: "michal", id: "id", action: :ignore}},
                     :profile, with: &Profile.set_action/2)
    assert changeset.changes == %{}
  end

  test "cast belongs_to with existing struct replacing" do
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

  test "cast belongs_to with optional" do
    changeset = cast(%Author{profile: %Profile{id: "id"}}, %{"profile" => nil}, :profile)
    assert changeset.changes.profile == nil
    assert changeset.valid?
  end

  test "cast belongs_to with custom changeset" do
    changeset = cast(%Author{}, %{"profile" => %{}}, :profile, with: &Profile.optional_changeset/2)
    assert (changeset.types.profile |> elem(1)).on_cast == &Profile.optional_changeset/2

    profile = changeset.changes.profile
    assert profile.data.__meta__.source == "authors_profiles"
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

  test "cast belongs_to with empty parameters" do
    changeset = cast(%Author{profile: nil}, %{}, :profile)
    assert changeset.changes == %{}

    changeset = cast(%Author{}, %{}, :profile, required: true)
    assert changeset.changes == %{}

    changeset = cast(%Author{profile: %Profile{}}, %{}, :profile, required: true)
    assert changeset.changes == %{}
  end

  test "cast belongs_to with on_replace: :raise" do
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

  test "cast belongs_to with on_replace: :mark_as_invalid" do
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

  test "cast belongs_to with keyword defaults" do
    {:ok, schema} = TestRepo.insert(%Author{title: "Title", profile: nil})

    changeset = cast(schema, %{"profile" => %{id: 1}}, :profile)
    assert changeset.changes.profile.data.name == "default"
    assert changeset.changes.profile.changes == %{id: 1}
  end

  test "cast belongs_to with atom defaults" do
    {:ok, schema} = TestRepo.insert(%Author{title: "Title", invalid_profile: nil})

    changeset = cast(schema, %{"invalid_profile" => %{name: "Jose"}}, :invalid_profile)
    assert_received {:defaults, %Profile{id: nil}, %Author{title: "Title"}, :default}
    assert changeset.changes.invalid_profile.data.id == 13
    assert changeset.changes.invalid_profile.changes == %{name: "Jose"}
  end

  test "cast belongs_to with MFA defaults" do
    {:ok, schema} = TestRepo.insert(%Author{title: "Title", update_profile: nil})

    changeset = cast(schema, %{"update_profile" => %{name: "Jose"}}, :update_profile)
    assert_received {:defaults, %Profile{id: nil}, %Author{title: "Title"}, :extra}
    assert changeset.changes.update_profile.data.id == 13
    assert changeset.changes.update_profile.changes == %{name: "Jose"}
  end

  test "cast belongs_to with on_replace: :update" do
    {:ok, schema} = TestRepo.insert(%Author{title: "Title",
      update_profile: %Profile{id: 1, name: "Enio"}})

    changeset = cast(schema, %{"update_profile" => %{id: 2, name: "Jose"}}, :update_profile)
    assert changeset.changes.update_profile.changes == %{name: "Jose", id: 2}
    assert changeset.changes.update_profile.action == :update
    assert changeset.errors == []
    assert changeset.valid?
  end

  test "cast belongs_to twice" do
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

  ## Change

  test "change belongs_to" do
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

  test "change belongs_to with attributes" do
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

    # Empty attributes
    assert {:ok, changeset, true} =
      Relation.change(assoc, %{}, profile)
    assert changeset.action == :insert
    assert changeset.changes == %{}

    assert {:ok, changeset, true} =
      Relation.change(assoc, [], profile)
    assert changeset.action == :insert
    assert changeset.changes == %{}
  end

  test "change belongs_to with struct" do
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

  test "change belongs_to keeps appropriate action from changeset" do
    assoc = Author.__schema__(:association, :profile)
    assoc_schema = %Profile{id: 1}

    # Adding
    changeset = %{Changeset.change(assoc_schema, name: "michal") | action: :insert}
    {:ok, changeset, _} = Relation.change(assoc, changeset, nil)
    assert changeset.action == :insert

    changeset = %{changeset | action: :update}
    {:ok, changeset, _} = Relation.change(assoc, changeset, nil)
    assert changeset.action == :update

    changeset = %{changeset | action: :delete}
    {:ok, changeset, _} = Relation.change(assoc, changeset, nil)
    assert changeset.action == :delete

    # Replacing
    changeset = %{Changeset.change(assoc_schema, name: "michal") | action: :insert}
    assert_raise RuntimeError, ~r/cannot insert related/, fn ->
      Relation.change(assoc, changeset, assoc_schema)
    end

    changeset = %{changeset | action: :update}
    {:ok, changeset, _} = Relation.change(assoc, changeset, assoc_schema)
    assert changeset.action == :update

    changeset = %{changeset | action: :delete}
    {:ok, changeset, _} = Relation.change(assoc, changeset, assoc_schema)
    assert changeset.action == :delete
  end

  test "change belongs_to with on_replace: :raise" do
    assoc_schema = %Profile{id: 1}
    base_changeset = Changeset.change(%Author{raise_profile: assoc_schema})

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :raise_profile, nil)
    end

    assert_raise RuntimeError, ~r"you are attempting to change relation", fn ->
      Changeset.put_assoc(base_changeset, :raise_profile, %Profile{id: 2})
    end
  end

  test "change belongs_to with on_replace: :mark_as_invalid" do
    assoc_schema = %Profile{id: 1}
    base_changeset = Changeset.change(%Author{invalid_profile: assoc_schema})

    changeset = Changeset.put_assoc(base_changeset, :invalid_profile, nil)
    assert changeset.changes == %{}
    assert changeset.errors == [invalid_profile: {"is invalid", [type: :map]}]
    refute changeset.valid?
  end

  ## Other

  test "put_assoc/4" do
    base_changeset = Changeset.change(%Author{})

    changeset = Changeset.put_assoc(base_changeset, :profile, %{name: "michal"})
    assert %Ecto.Changeset{} = changeset.changes.profile
    assert changeset.changes.profile.data.__meta__.source == "authors_profiles"

    changeset = Changeset.put_assoc(base_changeset, :profile, %Profile{name: "michal"})
    assert %Ecto.Changeset{} = changeset.changes.profile
    assert changeset.changes.profile.data.__meta__.source == "profiles"

    base_changeset = Changeset.change(%Author{profile: %Profile{name: "michal"}})
    empty_update_changeset = Changeset.change(%Profile{name: "michal"})

    changeset = Changeset.put_assoc(base_changeset, :profile, empty_update_changeset)
    refute Map.has_key?(changeset.changes, :profile)
  end

  test "put_assoc/4 with empty" do
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

    # On unloaded with change
    changeset =
      %Author{}
      |> Changeset.change(profile: %Profile{})
      |> Changeset.put_assoc(:profile, nil)

    assert Map.has_key?(changeset.changes, :profile)

    # On empty with change
    changeset =
      %Author{profile: nil}
      |> Changeset.change(profile: %Profile{})
      |> Changeset.put_assoc(:profile, nil)

    refute Map.has_key?(changeset.changes, :profile)
  end

  test "put_change/3" do
    changeset = Changeset.change(%Author{}, profile: %Profile{name: "michal"})
    assert %Ecto.Changeset{} = changeset.changes.profile

    base_changeset = Changeset.change(%Author{profile: %Profile{name: "michal"}})
    empty_update_changeset = Changeset.change(%Profile{name: "michal"})

    changeset = Changeset.put_change(base_changeset, :profile, empty_update_changeset)
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
    assert Changeset.fetch_field(changeset, :profile) == {:data, profile}
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

    changeset = Changeset.change(%Profile{}, name: "hello")
    changeset2 = %{changeset | action: :delete}
    assert Relation.apply_changes(embed, changeset2) == nil
  end
end
