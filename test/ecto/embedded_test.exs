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

    assert Author.__schema__(:embed, :profile) ==
      %Ecto.Embedded{field: :profile, cardinality: :one, owner: Author,
                     embed: Profile, container: nil}

    assert Author.__schema__(:embed, :profiles) ==
      %Ecto.Embedded{field: :profiles, cardinality: :many, owner: Author,
                     embed: Profile, container: :array}
  end
end
