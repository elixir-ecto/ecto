defmodule Ecto.Date do
  @moduledoc """
  An Ecto type for dates.
  """

  @behaviour Ecto.Type
  defstruct [:year, :month, :day]

  @doc """
  The Ecto primitive type.
  """
  def type, do: :date

  @doc """
  Casts to date.
  """
  def cast(%Ecto.Date{} = d), do: {:ok, d}
  def cast(_), do: :error

  @doc """
  Converts an `Ecto.Date` into a date triplet.
  """
  def dump(%Ecto.Date{year: year, month: month, day: day}) do
    {:ok, {year, month, day}}
  end

  @doc """
  Converts a date triplet into an `Ecto.Date`.
  """
  def load({year, month, day}) do
    {:ok, %Ecto.Date{year: year, month: month, day: day}}
  end

  @doc """
  Returns an `Ecto.Date` in local time.
  """
  def local do
    load(:erlang.date) |> elem(1)
  end

  @doc """
  Returns an `Ecto.Date` in UTC.
  """
  def utc do
    {date, _time} = :erlang.universaltime
    load(date) |> elem(1)
  end
end

defmodule Ecto.Time do
  @moduledoc """
  An Ecto type for time.
  """

  @behaviour Ecto.Type
  defstruct [:hour, :min, :sec]

  @doc """
  The Ecto primitive type.
  """
  def type, do: :time

  @doc """
  Casts to time.
  """
  def cast(%Ecto.Time{} = t), do: {:ok, t}
  def cast(_), do: :error

  @doc """
  Converts an `Ecto.Time` into a time triplet.
  """
  def dump(%Ecto.Time{hour: hour, min: min, sec: sec}) do
    {:ok, {hour, min, sec}}
  end

  @doc """
  Converts a time triplet into an `Ecto.Time`.
  """
  def load({hour, min, sec}) do
    {:ok, %Ecto.Time{hour: hour, min: min, sec: sec}}
  end

  @doc """
  Returns an `Ecto.Time` in local time.
  """
  def local do
    load(:erlang.time) |> elem(1)
  end

  @doc """
  Returns an `Ecto.Time` in UTC.
  """
  def utc do
    {_date, time} = :erlang.universaltime
    load(time) |> elem(1)
  end
end

defmodule Ecto.DateTime do
  @moduledoc """
  An Ecto type for dates and times.
  """

  @behaviour Ecto.Type
  defstruct [:year, :month, :day, :hour, :min, :sec]

  @doc """
  The Ecto primitive type.
  """
  def type, do: :datetime

  @doc """
  Casts to date time.
  """
  def cast(%Ecto.DateTime{} = dt), do: {:ok, dt}
  def cast(_), do: :error

  @doc """
  Converts an `Ecto.DateTime` into a `{date, time}` tuple.
  """
  def dump(%Ecto.DateTime{year: year, month: month, day: day, hour: hour, min: min, sec: sec}) do
    {:ok, {{year, month, day}, {hour, min, sec}}}
  end

  @doc """
  Converts a `{date, time}` tuple into an `Ecto.DateTime`.
  """
  def load({{year, month, day}, {hour, min, sec}}) do
    {:ok, %Ecto.DateTime{year: year, month: month, day: day,
                         hour: hour, min: min, sec: sec}}
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
    load(:erlang.localtime) |> elem(1)
  end

  @doc """
  Returns an `Ecto.DateTime` in UTC.
  """
  def utc do
    load(:erlang.universaltime) |> elem(1)
  end
end
