defmodule Friends.Person do
  import Ecto.Schema, only: [schema: 2]

  schema "people" do
    field :first_name, :string
    field :last_name, :string
    field :age, :integer
  end

  def changeset(person, params \\ %{}) do
    person
    |> Ecto.Changeset.cast(params, ~w(first_name last_name age))
    |> Ecto.Changeset.validate_required([:first_name, :last_name])
  end
end
