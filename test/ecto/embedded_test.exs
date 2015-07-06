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
    end
  end

  defmodule Profile do
    use Ecto.Model

    schema "" do
      field :name
    end
  end

  test "embeds_one" do
    assert Author.__schema__(:embeds) == [:profile]
  end

  ## Integration tests through Ecto.Model

  test "build_embedded/2" do
    assert build_embedded(%Author{}, :profile) ==
           %Profile{}
  end

  test "build_embedded/3 with custom attributes" do
    assert build_embedded(%Author{}, :profile, name: "Michal") ==
           %Profile{name: "Michal"}
  end
end
