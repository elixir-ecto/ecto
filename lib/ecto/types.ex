defmodule Ecto.Date do
  defstruct [:year, :month, :day]

  def to_erl(%Ecto.Date{year: year, month: month, day: day}) do
    {year, month, day}
  end

  def from_erl({year, month, day}) do
    %Ecto.Date{year: year, month: month, day: day}
  end
end

defmodule Ecto.Time do
  defstruct [:hour, :min, :sec]

  def to_erl(%Ecto.Time{hour: hour, min: min, sec: sec}) do
    {hour, min, sec}
  end

  def from_erl({hour, min, sec}) do
    %Ecto.Time{hour: hour, min: min, sec: sec}
  end
end

defmodule Ecto.DateTime do
  defstruct [:year, :month, :day, :hour, :min, :sec]

  def to_erl(%Ecto.DateTime{year: year, month: month, day: day, hour: hour, min: min, sec: sec}) do
    {{year, month, day}, {hour, min, sec}}
  end

  def from_erl({{year, month, day}, {hour, min, sec}}) do
    %Ecto.DateTime{year: year, month: month, day: day,
                   hour: hour, min: min, sec: sec}
  end

  def to_date(%Ecto.DateTime{year: year, month: month, day: day}) do
    %Ecto.Date{year: year, month: month, day: day}
  end

  def to_time(%Ecto.Time{hour: hour, min: min, sec: sec}) do
    %Ecto.Time{hour: hour, min: min, sec: sec}
  end

  def from_date_time(%Ecto.Date{year: year, month: month, day: day},
                     %Ecto.Time{hour: hour, min: min, sec: sec}) do
    %Ecto.DateTime{year: year, month: month, day: day,
                   hour: hour, min: min, sec: sec}
  end
end

defmodule Ecto.Interval do
  defstruct [:year, :month, :day, :hour, :min, :sec]
end

defmodule Ecto.Binary do
  @moduledoc false
  defstruct [:value]
end

defmodule Ecto.Array do
  @moduledoc false
  defstruct [:value, :type]
end
