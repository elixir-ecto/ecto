defmodule Ecto.DateTime.Util do
  @moduledoc false

  @doc false
  def zero_pad(val, count) do
    num = Integer.to_string(val)
    :binary.copy("0", count - byte_size(num)) <> num
  end

  @doc false
  def to_i(string) do
    String.to_integer(<<string::16>>)
  end

  @doc false
  def to_li(string) do
    String.to_integer(<<string::32>>)
  end

  @doc false
  defmacro valid_date(_year, month, day) do
    quote do
      unquote(month) in 1..12 and unquote(day) in 1..31
    end
  end

  @doc false
  defmacro valid_time(hour, min, sec) do
    quote do
      unquote(hour) in 0..23 and unquote(min) in 0..59 and unquote(sec) in 0..59
    end
  end

  @doc false
  defmacro valid_millis(m1, m2, m3) do
    quote do
      unquote(m1) in ?0..?9 and unquote(m2) in ?0..?9 and unquote(m3) in ?0..?9
    end
  end

  @doc false
  def valid_rest(<<>>), do: true
  def valid_rest(<< ?Z >>), do: true
  def valid_rest(<< ?., m1, m2, m3, rest::binary >>) when valid_millis(m1, m2, m3), do: valid_rest(rest)
  def valid_rest(_), do: false
end

defmodule Ecto.Date do
  import Ecto.DateTime.Util

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
  Dates are never blank.
  """
  def blank?(_), do: false

  @doc """
  Casts to date.
  """
  def cast(<<year::32, ?-, month::16, ?-, day::16>>),
    do: from_parts(to_li(year), to_i(month), to_i(day))
  def cast(%Ecto.Date{} = d),
    do: {:ok, d}
  def cast(_),
    do: :error

  defp from_parts(year, month, day) when valid_date(year, month, day) do
    {:ok, %Ecto.Date{year: year, month: month, day: day}}
  end
  defp from_parts(_, _, _), do: :error

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
  Converts `Ecto.Date` to its ISO 8601 string representation.
  """
  def to_string(%Ecto.Date{year: year, month: month, day: day}) do
    zero_pad(year, 4) <> "-" <> zero_pad(month, 2) <> "-" <> zero_pad(day, 2)
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
  import Ecto.DateTime.Util

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
  Times are never blank.
  """
  def blank?(_), do: false

  @doc """
  Casts to time.
  """
  def cast(<<hour::16, ?:, min::16, ?:, sec::16, rest::binary>>) do
    if valid_rest(rest) do from_parts(to_i(hour), to_i(min), to_i(sec)) else :error end
  end
  def cast(%Ecto.Time{} = t),
    do: {:ok, t}
  def cast(_),
    do: :error

  defp from_parts(hour, min, sec) when valid_time(hour, min, sec) do
    {:ok, %Ecto.Time{hour: hour, min: min, sec: sec}}
  end
  defp from_parts(_, _, _), do: :error

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
  Converts `Ecto.Time` to its ISO 8601 without timezone string representation.
  """
  def to_string(%Ecto.Time{hour: hour, min: min, sec: sec}) do
    zero_pad(hour, 2) <> ":" <> zero_pad(min, 2) <> ":" <> zero_pad(sec, 2)
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
  import Ecto.DateTime.Util

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
  Datetimes are never blank.
  """
  def blank?(_), do: false

  @doc """
  Casts to date time.
  """
  def cast(<<year::32, ?-, month::16, ?-, day::16, sep, hour::16, ?:, min::16, ?:, sec::16, rest::binary>>) when sep in [?\s, ?T] do
    if valid_rest(rest) do from_parts(to_li(year), to_i(month), to_i(day), to_i(hour), to_i(min), to_i(sec)) else :error end
  end
  def cast(%Ecto.DateTime{} = dt),
    do: {:ok, dt}
  def cast(_),
    do: :error

  defp from_parts(year, month, day, hour, min, sec)
      when valid_date(year, month, day) and valid_time(hour, min, sec) do
    {:ok, %Ecto.DateTime{year: year, month: month, day: day, hour: hour, min: min, sec: sec}}
  end
  defp from_parts(_, _, _, _, _, _), do: :error

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
  def to_time(%Ecto.DateTime{hour: hour, min: min, sec: sec}) do
    %Ecto.Time{hour: hour, min: min, sec: sec}
  end

  @doc """
  Converts `Ecto.DateTime` to its ISO 8601 UTC string representation.
  """
  def to_string(%Ecto.DateTime{year: year, month: month, day: day, hour: hour, min: min, sec: sec}) do
    zero_pad(year, 4) <> "-" <> zero_pad(month, 2) <> "-" <> zero_pad(day, 2) <> "T" <>
    zero_pad(hour, 2) <> ":" <> zero_pad(min, 2) <> ":" <> zero_pad(sec, 2) <> "Z"
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
