defmodule Ecto.EmbeddedTest do
  use ExUnit.Case, async: true
  doctest Ecto.Embedded

  import Ecto.Model
  import Ecto.Query, only: [from: 2]

  alias __MODULE__.Author
  alias __MODULE__.Profile


  defmodule Author do
    use Ecto.Model

    schema "authors" do
      embeds_one :profile, Profile
      embeds_many :profiles, Profile
    end
  end

  defmodule Profile do
    use Ecto.Model

    schema "" do
      field :name
    end
  end

  test "__schema__" do
    assert Author.__schema__(:embeds) == [:profile, :profiles]
    assert Author.__schema__(:embed, :profile).embedded == Profile
    assert Author.__schema__(:embed, :profile).embedded == Profile
  end

  ## Integration tests through Ecto.Model

  test "build_embedded/2" do
    assert build_embedded(%Author{}, :profile) == %Profile{}
    assert build_embedded(%Author{}, :profiles) == %Profile{}
  end

  test "build_embedded/3 with custom attributes" do
    assert build_embedded(%Author{}, :profile, name: "Michal") ==
      %Profile{name: "Michal"}
    assert build_embedded(%Author{}, :profiles, name: "Michal") ==
      %Profile{name: "Michal"}
  end
end
