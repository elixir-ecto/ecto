defmodule Custom.DateTime do
  defstruct [:year, :month, :day, :hour, :min, :sec]

  def blank?(_), do: false
  def type, do: :datetime

  def cast(%Custom.DateTime{} = datetime), do: {:ok, datetime}
  def cast(_), do: :error

  def load(%Ecto.DateTime{} = dt) do
    {:ok, %Custom.DateTime{year: dt.year, month: dt.month, day: dt.day,
                         hour: dt.hour, min: dt.min, sec: dt.sec}}
  end

  def dump(%Custom.DateTime{} = dt) do
    {:ok, %Ecto.DateTime{year: dt.year, month: dt.month, day: dt.day,
                         hour: dt.hour, min: dt.min, sec: dt.sec}}
  end
end
