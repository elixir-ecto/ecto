defmodule Ecto.Bench.CreateUser do
  use Ecto.Migration

  def change do
    create table(:users) do
      add(:name, :string)
      add(:email, :string)
      add(:password, :string)
      add(:time_attr, :time)
      add(:date_attr, :date)
      add(:naive_datetime_attr, :naive_datetime)
      add(:uuid, :binary_id)
    end
  end
end
