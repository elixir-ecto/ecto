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

    schema "" do
      field :name
    end

    def required_changeset(params, model \\ %Profile{}) do
      cast(model, params, ~w(name), ~w())
    end

    def optional_changeset(params, model \\ %Profile{}) do
      cast(model, params, ~w(), ~w(name))
    end
  end

  def other_changeset(params, model \\ %Profile{}) do
    cast(model, params, ~w(name), ~w())
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


  test "cast embed" do
    changeset = cast(%Author{}, %{"profile" => %{"name" => "michal"}}, ~w(profile))
    assert changeset.errors == []
    assert changeset.changes == %{[:profile, :name] => "michal"}
    assert changeset.valid?

    changeset = cast(%Author{}, %{"profile" => %{}}, ~w(profile))
    assert changeset.errors == [{[:profile, :name], "can't be blank"}]
    assert changeset.changes == %{}
    refute changeset.valid?
  end

  test "cast embed with custom changeset" do
    changeset = cast(%Author{}, %{"profile" => %{"name" => "michal"}}, [profile: :optional_changeset])
    assert changeset.errors == []
    assert changeset.changes == %{[:profile, :name] => "michal"}
    assert changeset.valid?

    changeset = cast(%Author{}, %{"profile" => %{}}, [profile: :optional_changeset])
    assert changeset.errors == []
    assert changeset.changes == %{}
    assert changeset.valid?
  end

  test "cast embed with custom changeset with module" do
    changeset = cast(%Author{}, %{"profile" => %{"name" => "michal"}}, [profile: {__MODULE__, :other_changeset}])
    assert changeset.errors == []
    assert changeset.changes == %{[:profile, :name] => "michal"}
    assert changeset.valid?
  end
end
