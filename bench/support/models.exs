defmodule Ecto.Bench.User do
  use Ecto.Schema

  schema "users" do
    field(:name, :string)
    field(:email, :string)
    field(:password, :string)
  end

  @required_attrs [:name, :email, :password]

  def changeset() do
    changeset(sample_data())
  end

  def changeset(data) do
    Ecto.Changeset.cast(%__MODULE__{}, data, @required_attrs)
  end

  def sample_data do
    %{
      name: "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
      email: "foobar@email.com",
      password: "mypass"
    }
  end
end
