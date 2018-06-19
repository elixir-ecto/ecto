defmodule Ecto.Bench.Migration do
  use Ecto.Migration

  def change do
    create table(:users) do
      add(:name, :string)
      add(:email, :string)
      add(:password, :string)
    end
  end
end

defmodule Ecto.Bench.User do
  use Ecto.Schema

  @required_attrs [:name, :email, :password]

  schema "users" do
    field(:name, :string)
    field(:email, :string)
    field(:password, :string)
  end

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
