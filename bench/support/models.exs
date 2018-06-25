defmodule Ecto.Bench.User do
  use Ecto.Schema

  schema "users" do
    field(:name, :string)
    field(:email, :string)
    field(:password, :string)
    field(:time_attr, :time)
    field(:date_attr, :date)
    field(:naive_datetime_attr, :naive_datetime)
    field(:uuid, :binary_id)
  end

  @required_attrs [
    :name,
    :email,
    :password,
    :time_attr,
    :date_attr,
    :naive_datetime_attr,
    :uuid
  ]

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
      password: "mypass",
      time_attr: Time.utc_now(),
      date_attr: Date.utc_today(),
      naive_datetime_attr: NaiveDateTime.utc_now(),
      uuid: Ecto.UUID.generate()
    }
  end
end

defmodule Ecto.Bench.Game do
  use Ecto.Schema

  schema "games" do
    field(:name, :string)
    field(:price, :float)
  end
end
