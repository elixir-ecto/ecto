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
      embeds_one :profile, Profile, changeset: :required_changeset
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
      cast(model, params, ~w(name), ~w())
    end

    def optional_changeset(params, model) do
      cast(model, params, ~w(), ~w(name))
    end
  end

  test "__schema__" do
    assert Author.__schema__(:embeds) == [:profile, :profiles]

    assert Author.__schema__(:embed, :profile) ==
      %Ecto.Embedded{field: :profile, cardinality: :one, owner: Author,
                     embed: Profile, container: nil, changeset: :required_changeset}

    assert Author.__schema__(:embed, :profiles) ==
      %Ecto.Embedded{field: :profiles, cardinality: :many, owner: Author,
                     embed: Profile, container: :array, changeset: :changeset}
  end


  test "cast embeds_one" do
    changeset = cast(%Author{}, %{"profile" => %{"name" => "michal"}}, ~w(profile))
    assert changeset.changes.profile.changes == %{name: "michal"}
    assert changeset.changes.profile.errors == []
    assert changeset.changes.profile.valid?
    assert changeset.valid?

    changeset = cast(%Author{}, %{"profile" => %{}}, ~w(profile))
    assert changeset.changes.profile.changes == %{}
    assert changeset.changes.profile.errors  == [name: "can't be blank"]
    refute changeset.changes.profile.valid?
    refute changeset.valid?

    changeset = cast(%Author{profile: %Profile{name: "michal"}},
                     %{"profile" => %{}}, ~w(profile))
    assert changeset.changes.profile.changes == %{}
    assert changeset.changes.profile.errors  == []
    assert changeset.changes.profile.valid?
    assert changeset.valid?
  end

  test "cast embeds_one with custom changeset" do
    changeset = cast(%Author{}, %{"profile" => %{"name" => "michal"}}, [profile: :optional_changeset])
    assert changeset.changes.profile.changes == %{name: "michal"}
    assert changeset.changes.profile.errors == []
    assert changeset.changes.profile.valid?
    assert changeset.valid?

    changeset = cast(%Author{}, %{"profile" => %{}}, [profile: :optional_changeset])
    assert changeset.changes.profile.changes == %{}
    assert changeset.changes.profile.errors == []
    assert changeset.changes.profile.valid?
    assert changeset.valid?
  end

  test "cast embeds_many with only new models" do
    changeset = cast(%Author{}, %{"profiles" => [%{"name" => "michal"}]}, ~w(profiles))
    [profile_change] = changeset.changes.profiles
    assert profile_change.changes == %{name: "michal"}
    assert profile_change.errors == []
    assert profile_change.valid?
    assert changeset.valid?
  end

  # Please note the order is important in this test.
  test "cast embeds_many updating old models" do
    profiles = [%Profile{name: "michal", id: "michal"},
                %Profile{name: "unknown", id: "unknown"},
                %Profile{name: "other", id: "other"}]
    params = [%{"id" => "unknown", "name" => nil},
              %{"id" => "other", "name" => "new name"}]

    changeset = cast(%Author{profiles: profiles}, %{"profiles" => params}, ~w(profiles))
    [unknown, other, michal] = changeset.changes.profiles
    assert unknown.model.id == "unknown"
    assert unknown.errors == [name: "can't be blank"]
    refute unknown.valid?
    assert other.model.id == "other"
    assert other.valid?
    assert michal.model.id == "michal"
    assert michal.valid?
    refute changeset.valid?
  end
end
