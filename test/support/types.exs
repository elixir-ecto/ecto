defmodule Custom.DateTime do
  defstruct [:year, :month, :day, :hour, :min, :sec]

  def blank?(_), do: false
  def type, do: :datetime

  def cast(%Custom.DateTime{} = datetime), do: {:ok, datetime}
  def cast(_), do: :error

  def load({{year, month, day}, {hour, min, sec}}) do
    {:ok, %Custom.DateTime{year: year, month: month, day: day,
                           hour: hour, min: min, sec: sec}}
  end

  def dump(%Custom.DateTime{} = dt) do
    {:ok, {{dt.year, dt.month, dt.day}, {dt.hour, dt.min, dt.sec}}}
  end
end
