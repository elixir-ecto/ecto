defmodule Ecto.Date do
  @moduledoc """
  An Ecto type for dates.
  """

  defstruct [:year, :month, :day]

  @doc """
  Converts an `Ecto.Date` into a date triplet.
  """
  def to_erl(%Ecto.Date{year: year, month: month, day: day}) do
    {year, month, day}
  end

  @doc """
  Converts a date triplet into an `Ecto.Date`.
  """
  def from_erl({year, month, day}) do
    %Ecto.Date{year: year, month: month, day: day}
  end

  @doc """
  Returns an `Ecto.Date` in local time.
  """
  def local do
    from_erl(:erlang.date)
  end

  @doc """
  Returns an `Ecto.Date` in UTC.
  """
  def utc do
    {date, _time} = :erlang.universaltime
    from_erl(date)
  end
end

defmodule Ecto.Time do
  @moduledoc """
  An Ecto type for time.
  """

  defstruct [:hour, :min, :sec]

  @doc """
  Converts an `Ecto.Time` into a time triplet.
  """
  def to_erl(%Ecto.Time{hour: hour, min: min, sec: sec}) do
    {hour, min, sec}
  end

  @doc """
  Converts a time triplet into an `Ecto.Time`.
  """
  def from_erl({hour, min, sec}) do
    %Ecto.Time{hour: hour, min: min, sec: sec}
  end

  @doc """
  Returns an `Ecto.Time` in local time.
  """
  def local do
    from_erl(:erlang.time)
  end

  @doc """
  Returns an `Ecto.Time` in UTC.
  """
  def utc do
    {_date, time} = :erlang.universaltime
    from_erl(time)
  end
end

defmodule Ecto.DateTime do
  @moduledoc """
  An Ecto type for dates and times.
  """

  defstruct [:year, :month, :day, :hour, :min, :sec]

  @doc """
  The Ecto primitive type.
  """
  def type, do: :datetime

  @doc """
  Converts an `Ecto.DateTime` into a `{date, time}` tuple.
  """
  def to_erl(%Ecto.DateTime{year: year, month: month, day: day, hour: hour, min: min, sec: sec}) do
    {{year, month, day}, {hour, min, sec}}
  end

  @doc """
  Converts a `{date, time}` tuple into an `Ecto.DateTime`.
  """
  def from_erl({{year, month, day}, {hour, min, sec}}) do
    %Ecto.DateTime{year: year, month: month, day: day,
                   hour: hour, min: min, sec: sec}
  end

  @doc """
  Converts `Ecto.DateTime` into an `Ecto.Date`.
  """
  def to_date(%Ecto.DateTime{year: year, month: month, day: day}) do
    %Ecto.Date{year: year, month: month, day: day}
  end

  @doc """
  Converts `Ecto.DateTime` into an `Ecto.Time`.
  """
  def to_time(%Ecto.Time{hour: hour, min: min, sec: sec}) do
    %Ecto.Time{hour: hour, min: min, sec: sec}
  end

  @doc """
  Converts the given `Ecto.Date` and `Ecto.Time` into `Ecto.DateTime`.
  """
  def from_date_and_time(%Ecto.Date{year: year, month: month, day: day},
                         %Ecto.Time{hour: hour, min: min, sec: sec}) do
    %Ecto.DateTime{year: year, month: month, day: day,
                   hour: hour, min: min, sec: sec}
  end

  @doc """
  Returns an `Ecto.DateTime` in local time.
  """
  def local do
    from_erl(:erlang.localtime)
  end

  @doc """
  Returns an `Ecto.DateTime` in UTC.
  """
  def utc do
    from_erl(:erlang.universaltime)
  end
end
