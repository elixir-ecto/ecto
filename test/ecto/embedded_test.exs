defmodule Ecto.EmbeddedTest do
  use ExUnit.Case, async: true
  doctest Ecto.Embedded

  import Ecto.Model
  import Ecto.Query, only: [from: 2]
  import Ecto.Changeset

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

    def changeset(params, model) do
      cast(model, params, ~w(name))
    end

    def required_changeset(params, model) do
      cast(model, params, ~w(name), ~w(id))
    end

    def optional_changeset(params, model) do
      cast(model, params, ~w(), ~w(name))
    end
  end

  test "__schema__" do
    assert Author.__schema__(:embeds) == [:profile, :profiles]

    assert Author.__schema__(:embed, :profile) ==
      %Ecto.Embedded{field: :profile, cardinality: :one, owner: Author,
                     embed: Profile, container: nil, on_cast: :required_changeset}

    assert Author.__schema__(:embed, :profiles) ==
      %Ecto.Embedded{field: :profiles, cardinality: :many, owner: Author,
                     embed: Profile, container: :array, on_cast: :changeset}
  end

  test "cast embeds_one with valid params" do
    changeset = cast(%Author{}, %{"profile" => %{"name" => "michal"}}, ~w(profile))
    profile = changeset.changes.profile
    assert profile.changes == %{name: "michal"}
    assert profile.errors == []
    assert profile.status  == :insert
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast embeds_one with invalid params" do
    changeset = cast(%Author{}, %{"profile" => %{}}, ~w(profile))
    assert changeset.changes.profile.changes == %{}
    assert changeset.changes.profile.errors  == [name: "can't be blank"]
    assert changeset.changes.profile.status  == :insert
    refute changeset.changes.profile.valid?
    refute changeset.valid?

    changeset = cast(%Author{}, %{"profile" => "value"}, ~w(profile))
    assert changeset.errors == [profile: "is invalid"]
    refute changeset.valid?
  end

  test "cast embeds_one with existing model updating" do
    changeset = cast(%Author{profile: %Profile{name: "michal", id: "michal"}},
                     %{"profile" => %{"name" => "new", "id" => "michal"}}, ~w(profile))
    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.status  == :update
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast embeds_one with existing model replacing" do
    changeset = cast(%Author{profile: %Profile{name: "michal", id: "michal"}},
                     %{"profile" => %{"name" => "new"}}, ~w(profile))
    profile = changeset.changes.profile
    assert profile.changes == %{name: "new"}
    assert profile.errors  == []
    assert profile.status  == :insert
    assert profile.valid?
    assert changeset.valid?

    changeset = cast(%Author{profile: %Profile{name: "michal", id: "michal"}},
                     %{"profile" => %{"name" => "new", "id" => "new"}}, ~w(profile))
    profile = changeset.changes.profile
    assert profile.changes == %{name: "new", id: "new"}
    assert profile.errors  == []
    assert profile.status  == :insert
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast embeds_one with custom changeset" do
    changeset = cast(%Author{}, %{"profile" => %{"name" => "michal"}},
                     [profile: :optional_changeset])
    profile = changeset.changes.profile
    assert profile.changes == %{name: "michal"}
    assert profile.errors  == []
    assert profile.status  == :insert
    assert profile.valid?
    assert changeset.valid?

    changeset = cast(%Author{}, %{"profile" => %{}}, [profile: :optional_changeset])
    profile = changeset.changes.profile
    assert profile.changes == %{}
    assert profile.errors  == []
    assert profile.status  == :insert
    assert profile.valid?
    assert changeset.valid?
  end

  test "cast embeds_many with only new models" do
    changeset = cast(%Author{}, %{"profiles" => [%{"name" => "michal"}]}, ~w(profiles))
    [profile_change] = changeset.changes.profiles
    assert profile_change.changes == %{name: "michal"}
    assert profile_change.errors  == []
    assert profile_change.status  == :insert
    assert profile_change.valid?
    assert changeset.valid?
  end

  test "cast embeds_many with custom changeset" do
    changeset = cast(%Author{}, %{"profiles" => [%{"name" => "michal"}]},
                     [profiles: :optional_changeset])
    [profile_change] = changeset.changes.profiles
    assert profile_change.changes == %{name: "michal"}
    assert profile_change.errors  == []
    assert profile_change.status  == :insert
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

    changeset = cast(%Author{profiles: profiles}, %{"profiles" => params}, ~w(profiles))
    [new, unknown, other, michal] = changeset.changes.profiles
    assert new.changes == %{name: "new"}
    assert new.status == :insert
    assert new.valid?
    assert unknown.model.id == "unknown"
    assert unknown.errors == [name: "can't be blank"]
    assert unknown.status == :update
    refute unknown.valid?
    assert other.model.id == "other"
    assert other.status == :update
    assert other.valid?
    assert michal.model.id == "michal"
    assert michal.required == [] # Check for not running chgangeset function
    assert michal.status == :delete
    assert michal.valid?
    refute changeset.valid?
  end

  test "cast embeds_many with invalid params" do
    changeset = cast(%Author{}, %{"profiles" => "value"}, ~w(profiles))
    assert changeset.errors == [profiles: "is invalid"]
    refute changeset.valid?

    changeset = cast(%Author{}, %{"profiles" => ["value"]}, ~w(profiles))
    assert changeset.errors == [profiles: "is invalid"]
    refute changeset.valid?

    changeset = cast(%Author{}, %{"profiles" => nil}, ~w(profiles))
    assert changeset.errors == [profiles: "is invalid"]
    refute changeset.valid?
  end
end
