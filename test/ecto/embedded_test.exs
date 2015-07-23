defmodule Ecto.EmbeddedTest do
  use ExUnit.Case, async: true
  doctest Ecto.Embedded

  alias Ecto.Changeset
  alias Ecto.Embedded

  alias __MODULE__.Author
  alias __MODULE__.Profile

  defmodule Author do
    use Ecto.Model

    schema "authors" do
      embeds_one :profile, Profile, on_cast: :required_changeset
      embeds_many :profiles, Profile
    end
  end

  defmodule Profile do
    use Ecto.Model

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "" do
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
    assert Author.__schema__(:embeds) == [:profile, :profiles]

    assert Author.__schema__(:embed, :profile) ==
      %Embedded{field: :profile, cardinality: :one, owner: Author,
                embed: Profile, strategy: :replace, on_cast: :required_changeset}

    assert Author.__schema__(:embed, :profiles) ==
      %Embedded{field: :profiles, cardinality: :many, owner: Author,
                embed: Profile, strategy: :replace, on_cast: :changeset}
  end

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
    assert changeset.changes == %{profile: nil}
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

  test "cast embeds_one keeps action from changeset" do
    changeset = Changeset.cast(%Author{}, %{"profile" => %{"name" => "michal"}},
                               [profile: :set_action])
    assert changeset.changes.profile.action == :update
  end

  test "cast embeds_many with only new models" do
    changeset = Changeset.cast(%Author{}, %{"profiles" => [%{"name" => "michal"}]}, ~w(profiles))
    [profile_change] = changeset.changes.profiles
    assert profile_change.changes == %{name: "michal"}
    assert profile_change.errors  == []
    assert profile_change.action  == :insert
    assert profile_change.valid?
    assert changeset.valid?
  end

  test "cast embeds_many with map" do
    changeset = Changeset.cast(%Author{}, %{"profiles" => %{0 => %{"name" => "michal"}}}, ~w(profiles))
    [profile_change] = changeset.changes.profiles
    assert profile_change.changes == %{name: "michal"}
    assert profile_change.errors  == []
    assert profile_change.action  == :insert
    assert profile_change.valid?
    assert changeset.valid?
  end

  test "cast embeds_many with custom changeset" do
    changeset = Changeset.cast(%Author{}, %{"profiles" => [%{"name" => "michal"}]},
                               [profiles: :optional_changeset])
    [profile_change] = changeset.changes.profiles
    assert profile_change.changes == %{name: "michal"}
    assert profile_change.errors  == []
    assert profile_change.action  == :insert
    assert profile_change.valid?
    assert changeset.valid?
  end

  # Please note the order is important in this test.
  test "cast embeds_many changing models" do
    profiles = [%Profile{name: "michal", id: "michal"},
                %Profile{name: "unknown", id: "unknown"},
                %Profile{name: "other", id: "other"}]
    params = [%{"id" => "new", "name" => "new"},
              %{"id" => "unknown", "name" => nil},
              %{"id" => "other", "name" => "new name"}]

    changeset = Changeset.cast(%Author{profiles: profiles},
                               %{"profiles" => params}, ~w(profiles))
    [new, unknown, other, michal] = changeset.changes.profiles
    assert new.changes == %{name: "new"}
    assert new.action == :insert
    assert new.valid?
    assert unknown.model.id == "unknown"
    assert unknown.errors == [name: "can't be blank"]
    assert unknown.action == :update
    refute unknown.valid?
    assert other.model.id == "other"
    assert other.action == :update
    assert other.valid?
    assert michal.model.id == "michal"
    assert michal.required == [] # Check for not running chgangeset function
    assert michal.action == :delete
    assert michal.valid?
    refute changeset.valid?
  end

  test "cast embeds_many with invalid params" do
    changeset = Changeset.cast(%Author{}, %{"profiles" => "value"}, ~w(profiles))
    assert changeset.errors == [profiles: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.cast(%Author{}, %{"profiles" => ["value"]}, ~w(profiles))
    assert changeset.errors == [profiles: "is invalid"]
    refute changeset.valid?

    changeset = Changeset.cast(%Author{}, %{"profiles" => nil}, ~w(profiles))
    assert changeset.errors == [profiles: "is invalid"]
    refute changeset.valid?
  end

  test "cast embeds_many without changes skips" do
    changeset =
      Changeset.cast(%Author{profiles: [%Profile{name: "michal", id: "michal"}]},
                     %{"profiles" => [%{"id" => "michal"}]}, ~w(profiles))

    refute Map.has_key?(changeset.changes, :profiles)
  end

  test "cast embeds_many when required" do
    changeset =
      Changeset.cast(%Author{profiles: []}, %{}, ~w(profiles))
    assert changeset.changes == %{}
    assert changeset.errors == []

    changeset =
      Changeset.cast(%Author{profiles: []}, %{"profiles" => nil}, ~w(profiles))
    assert changeset.changes == %{}
    assert changeset.errors == [profiles: "is invalid"]
  end

  test "change embeds_one" do
    embed = %Embedded{field: :profile, cardinality: :one, owner: Author, embed: Profile}

    assert {:ok, changeset, true, false} =
      Embedded.change(embed, %Profile{name: "michal"}, nil)
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, name: "michal"}

    assert {:ok, changeset, true, false} =
      Embedded.change(embed, %Profile{name: "michal"}, %Profile{})
    assert changeset.action == :update
    assert changeset.changes == %{name: "michal"}

    assert {:ok, changeset, true, false} = Embedded.change(embed, nil, %Profile{})
    assert changeset.action == :delete

    model = %Profile{}
    model_changeset = Changeset.change(model, name: "michal")

    assert {:ok, changeset, true, false} = Embedded.change(embed, model_changeset, nil)
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, name: "michal"}

    assert {:ok, changeset, true, false} = Embedded.change(embed, model_changeset, model)
    assert changeset.action == :update
    assert changeset.changes == %{name: "michal"}

    empty_changeset = Changeset.change(model)
    assert {:ok, _, true, true} = Embedded.change(embed, empty_changeset, model)
  end

  test "change embeds_one keeps action from changeset" do
    embed = %Embedded{field: :profile, cardinality: :one, owner: Author, embed: Profile}

    changeset =
      %Profile{}
      |> Changeset.change(name: "michal")
      |> Map.put(:action, :update)

    {:ok, changeset, _, _} = Embedded.change(embed, changeset, nil)
    assert changeset.action == :update
  end

  test "change embeds_many" do
    embed = %Embedded{field: :profiles, cardinality: :many, owner: Author, embed: Profile}

    assert {:ok, [changeset], true, false} =
      Embedded.change(embed, [%Profile{name: "michal"}], [])
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, name: "michal"}

    assert {:ok, [changeset], true, false} =
      Embedded.change(embed, [%Profile{id: 1, name: "michal"}], [%Profile{id: 1}])
    assert changeset.action == :update
    assert changeset.changes == %{name: "michal"}

    assert {:ok, [new, old], true, false} =
      Embedded.change(embed, [%Profile{name: "michal"}], [%Profile{id: 1}])
    assert new.action == :insert
    assert new.changes == %{id: nil, name: "michal"}
    assert old.action == :delete
    assert old.model.id == 1

    model_changeset = Changeset.change(%Profile{}, name: "michal")

    assert {:ok, [changeset], true, false} = Embedded.change(embed, [model_changeset], [])
    assert changeset.action == :insert
    assert changeset.changes == %{id: nil, name: "michal"}

    model = %Profile{id: 1}
    model_changeset = Changeset.change(model, name: "michal")
    assert {:ok, [changeset], true, false} = Embedded.change(embed, [model_changeset], [model])
    assert changeset.action == :update
    assert changeset.changes == %{name: "michal"}

    assert {:ok, [changeset], true, false} = Embedded.change(embed, [], [model_changeset])
    assert changeset.action == :delete

    empty_changeset = Changeset.change(model)
    assert {:ok, _, true, true} = Embedded.change(embed, [empty_changeset], [model])
    assert {:ok, _, true, false} = Embedded.change(embed, [empty_changeset, model_changeset], [model, model])
  end

  test "empty" do
    assert Embedded.empty(%Embedded{cardinality: :one}) == nil
    assert Embedded.empty(%Embedded{cardinality: :many}) == []
  end

  test "apply_changes" do
    embed = %Embedded{field: :profile, cardinality: :one, owner: Author, embed: Profile}

    changeset = Changeset.change(%Profile{}, name: "michal")
    model = Embedded.apply_changes(embed, changeset)
    assert model == %Profile{name: "michal"}

    changeset2 = %{changeset | action: :delete}
    assert Embedded.apply_changes(embed, changeset2) == nil

    embed = %Embedded{field: :profiles, cardinality: :many, owner: Author, embed: Profile}
    [model] = Embedded.apply_changes(embed, [changeset, changeset2])
    assert model == %Profile{name: "michal"}
  end
end
