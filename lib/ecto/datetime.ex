import Kernel, except: [to_string: 1]

defmodule Ecto.DateTime.Util do
  @moduledoc false

  @doc "Pads with zero"
  def zero_pad(val, count) do
    num = Integer.to_string(val)
    :binary.copy("0", count - byte_size(num)) <> num
  end

  @doc "Converts to integer if possible"
  def to_i(nil), do: nil
  def to_i(int) when is_integer(int), do: int
  def to_i(bin) when is_binary(bin) do
    case Integer.parse(bin) do
      {int, ""} -> int
      _ -> nil
    end
  end

  @doc "A guard to check for dates"
  defmacro is_date(_year, month, day) do
    quote do
      unquote(month) in 1..12 and unquote(day) in 1..31
    end
  end

  @doc "A guard to check for times"
  defmacro is_time(hour, min, sec, usec \\ 0) do
    quote do
      unquote(hour) in 0..23 and
        unquote(min) in 0..59 and
        unquote(sec) in 0..59 and
        unquote(usec) in 0..999_999
    end
  end

  @doc """
  Checks if the trailing part of a date/time matches ISO specs.
  """
  defmacro is_iso_8601(x) do
    quote do: unquote(x) in ["", "Z"]
  end

  @doc """
  Gets microseconds from rest and validates it.

  Returns nil if an invalid format is given.
  """
  def usec("." <> rest) do
    case parse(rest, "") do
      {int, rest} when byte_size(int) in 1..6 and is_iso_8601(rest) ->
        pad = String.duplicate("0", 6 - byte_size(int))
        String.to_integer(int <> pad)
      _ ->
        nil
    end
  end
  def usec(rest) when is_iso_8601(rest), do: 0
  def usec(_), do: nil

  defp parse(<<h, t::binary>>, acc) when h in ?0..?9, do: parse(t, <<acc::binary, h>>)
  defp parse(rest, acc), do: {acc, rest}
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
  Casts to date.
  """
  def cast(<<year::4-bytes, ?-, month::2-bytes, ?-, day::2-bytes>>),
    do: from_parts(to_i(year), to_i(month), to_i(day))
  def cast(<<year::4-bytes, ?-, month::2-bytes, ?-, day::1-bytes>>),
    do: from_parts(to_i(year), to_i(month), to_i(day))
  def cast(<<year::4-bytes, ?-, month::1-bytes, ?-, day::2-bytes>>),
    do: from_parts(to_i(year), to_i(month), to_i(day))
  def cast(<<year::4-bytes, ?-, month::1-bytes, ?-, day::1-bytes>>),
    do: from_parts(to_i(year), to_i(month), to_i(day))
  def cast(%Ecto.Date{} = d),
    do: {:ok, d}
  def cast(%{"year" => year, "month" => month, "day" => day}),
    do: from_parts(to_i(year), to_i(month), to_i(day))
  def cast(%{year: year, month: month, day: day}),
    do: from_parts(to_i(year), to_i(month), to_i(day))
  def cast(_),
    do: :error

  defp from_parts(year, month, day) when is_date(year, month, day) do
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
  Converts `Ecto.Date` to a readable string representation.
  """
  def to_string(%Ecto.Date{year: year, month: month, day: day}) do
    zero_pad(year, 4) <> "-" <> zero_pad(month, 2) <> "-" <> zero_pad(day, 2)
  end

  @doc """
  Converts `Ecto.Date` to ISO8601 representation.
  """
  def to_iso8601(date) do
    to_string(date)
  end

  @doc """
  Returns an `Ecto.Date` in local time.
  """
  def local do
    erl_load(:erlang.localtime)
  end

  @doc """
  Returns an `Ecto.Date` in UTC.
  """
  def utc do
    erl_load(:erlang.universaltime)
  end

  @doc """
  Returns an Erlang date tuple from an `Ecto.Date`.
  """
  def to_erl(%Ecto.Date{year: year, month: month, day: day}) do
    {year, month, day}
  end

  @doc """
  Returns an `Ecto.Date` from an Erlang date tuple.
  """
  def from_erl({year, month, day}) do
    %Ecto.Date{year: year, month: month, day: day}
  end

  defp erl_load({{year, month, day}, _time}) do
    %Ecto.Date{year: year, month: month, day: day}
  end
end

defmodule Ecto.Time do
  import Ecto.DateTime.Util

  @moduledoc """
  An Ecto type for time.
  """

  @behaviour Ecto.Type
  defstruct [:hour, :min, :sec, usec: 0]

  @doc """
  The Ecto primitive type.
  """
  def type, do: :time

  @doc """
  Casts to time.
  """
  def cast(<<hour::2-bytes, ?:, min::2-bytes, ?:, sec::2-bytes, rest::binary>>) do
    if usec = usec(rest) do
      from_parts(to_i(hour), to_i(min), to_i(sec), usec)
    else
      :error
    end
  end
  def cast(%Ecto.Time{} = t),
    do: {:ok, t}
  def cast(%{"hour" => hour, "min" => min} = map),
    do: from_parts(to_i(hour), to_i(min), to_i(Map.get(map, "sec", 0)), to_i(Map.get(map, "usec", 0)))
  def cast(%{hour: hour, min: min} = map),
    do: from_parts(to_i(hour), to_i(min), to_i(Map.get(map, :sec, 0)), to_i(Map.get(map, :usec, 0)))
  def cast(_),
    do: :error

  defp from_parts(hour, min, sec, usec) when is_time(hour, min, sec, usec),
    do: {:ok, %Ecto.Time{hour: hour, min: min, sec: sec, usec: usec}}
  defp from_parts(_, _, _, _),
    do: :error

  @doc """
  Converts an `Ecto.Time` into a time tuple (in the form `{hour, min, sec,
  usec}`).
  """
  def dump(%Ecto.Time{hour: hour, min: min, sec: sec, usec: usec}) do
    {:ok, {hour, min, sec, usec}}
  end

  @doc """
  Converts a time tuple like the one returned by `dump/1` into an `Ecto.Time`.
  """
  def load({hour, min, sec, usec}) do
    {:ok, %Ecto.Time{hour: hour, min: min, sec: sec, usec: usec}}
  end

  @doc """
  Converts `Ecto.Time` to a string representation.
  """
  def to_string(%Ecto.Time{hour: hour, min: min, sec: sec, usec: usec}) do
    str = zero_pad(hour, 2) <> ":" <> zero_pad(min, 2) <> ":" <> zero_pad(sec, 2)

    if is_nil(usec) or usec == 0 do
      str
    else
      str <> "." <> zero_pad(usec, 6)
    end
  end

  @doc """
  Converts `Ecto.Time` to its ISO 8601 UTC representation.
  """
  def to_iso8601(time) do
    to_string(time)
  end

  @doc """
  Returns an `Ecto.Time` in local time.
  """
  def local do
    erl_load(:erlang.localtime)
  end

  @doc """
  Returns an `Ecto.Time` in UTC.
  """
  def utc do
    erl_load(:erlang.universaltime)
  end

  @doc """
  Returns an Erlang time tuple from an `Ecto.Time`.
  """
  def to_erl(%Ecto.Time{hour: hour, min: min, sec: sec}) do
    {hour, min, sec}
  end

  @doc """
  Returns an `Ecto.Time` from an Erlang time tuple.
  """
  def from_erl({hour, min, sec}) do
    %Ecto.Time{hour: hour, min: min, sec: sec}
  end

  defp erl_load({_, {hour, min, sec}}) do
    %Ecto.Time{hour: hour, min: min, sec: sec}
  end
end

defmodule Ecto.DateTime do
  import Ecto.DateTime.Util

  @moduledoc """
  An Ecto type that includes a date and a time.
  """

  @behaviour Ecto.Type
  defstruct [:year, :month, :day, :hour, :min, :sec, usec: 0]

  @doc """
  The Ecto primitive type.
  """
  def type, do: :datetime

  @doc """
  Casts to date time.
  """
  def cast(<<year::4-bytes, ?-, month::2-bytes, ?-, day::2-bytes, sep,
             hour::2-bytes, ?:, min::2-bytes, ?:, sec::2-bytes, rest::binary>>) when sep in [?\s, ?T] do
    if usec = usec(rest) do
      from_parts(to_i(year), to_i(month), to_i(day),
                 to_i(hour), to_i(min), to_i(sec), usec)
    else
      :error
    end
  end

  def cast(%Ecto.DateTime{} = dt) do
    {:ok, dt}
  end

  def cast(%{"year" => year, "month" => month, "day" => day, "hour" => hour, "min" => min} = map) do
    from_parts(to_i(year), to_i(month), to_i(day),
               to_i(hour), to_i(min), to_i(Map.get(map, "sec", 0)),
               to_i(Map.get(map, "usec", 0)))
  end

  def cast(%{year: year, month: month, day: day, hour: hour, min: min} = map) do
    from_parts(to_i(year), to_i(month), to_i(day),
               to_i(hour), to_i(min), to_i(Map.get(map, :sec, 0)),
               to_i(Map.get(map, :usec, 0)))
  end

  def cast(_) do
    :error
  end

  defp from_parts(year, month, day, hour, min, sec, usec)
      when is_date(year, month, day) and is_time(hour, min, sec, usec) do
    {:ok, %Ecto.DateTime{year: year, month: month, day: day, hour: hour, min: min, sec: sec, usec: usec}}
  end
  defp from_parts(_, _, _, _, _, _, _), do: :error

  @doc """
  Converts an `Ecto.DateTime` into a `{date, time}` tuple.
  """
  def dump(%Ecto.DateTime{year: year, month: month, day: day, hour: hour, min: min, sec: sec, usec: usec}) do
    {:ok, {{year, month, day}, {hour, min, sec, usec}}}
  end

  @doc """
  Converts a `{date, time}` tuple into an `Ecto.DateTime`.
  """
  def load({{year, month, day}, {hour, min, sec, usec}}) do
    {:ok, %Ecto.DateTime{year: year, month: month, day: day,
                         hour: hour, min: min, sec: sec, usec: usec}}
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
  def to_time(%Ecto.DateTime{hour: hour, min: min, sec: sec, usec: usec}) do
    %Ecto.Time{hour: hour, min: min, sec: sec, usec: usec}
  end

  @doc """
  Converts the given `Ecto.Date` into `Ecto.DateTime`.

  The time component is zero.
  """
  def from_date(%Ecto.Date{year: year, month: month, day: day}) do
    %Ecto.DateTime{year: year, month: month, day: day,
      hour: 0, min: 0, sec: 0, usec: 0}
  end

  @doc """
  Converts the given `Ecto.Date` and `Ecto.Time` into `Ecto.DateTime`.
  """
  def from_date_and_time(%Ecto.Date{year: year, month: month, day: day},
                         %Ecto.Time{hour: hour, min: min, sec: sec, usec: usec}) do
    %Ecto.DateTime{year: year, month: month, day: day,
                   hour: hour, min: min, sec: sec, usec: usec}
  end

  @doc """
  Converts `Ecto.DateTime` to its string representation.
  """
  def to_string(%Ecto.DateTime{year: year, month: month, day: day, hour: hour, min: min, sec: sec, usec: usec}) do
    str = zero_pad(year, 4) <> "-" <> zero_pad(month, 2) <> "-" <> zero_pad(day, 2) <> " " <>
          zero_pad(hour, 2) <> ":" <> zero_pad(min, 2) <> ":" <> zero_pad(sec, 2)

    if is_nil(usec) or usec == 0 do
      str
    else
      str <> "." <> zero_pad(usec, 6)
    end
  end

  @doc """
  Converts `Ecto.DateTime` to its ISO 8601 UTC representation.
  """
  def to_iso8601(%Ecto.DateTime{year: year, month: month, day: day, hour: hour, min: min, sec: sec, usec: usec}) do
    str = zero_pad(year, 4) <> "-" <> zero_pad(month, 2) <> "-" <> zero_pad(day, 2) <> "T" <>
          zero_pad(hour, 2) <> ":" <> zero_pad(min, 2) <> ":" <> zero_pad(sec, 2)

    if is_nil(usec) or usec == 0 do
      str <> "Z"
    else
      str <> "." <> zero_pad(usec, 6) <> "Z"
    end
  end

  @doc """
  Returns an `Ecto.DateTime` in local time.
  """
  def local do
    erl_load(:erlang.localtime)
  end

  @doc """
  Returns an `Ecto.DateTime` in UTC.
  """
  def utc do
    erl_load(:erlang.universaltime)
  end

  @doc """
  Returns an Erlang datetime tuple from an `Ecto.DateTime`.
  """
  def to_erl(%Ecto.DateTime{year: year, month: month, day: day, hour: hour, min: min, sec: sec}) do
    {{year, month, day}, {hour, min, sec}}
  end

  @doc """
  Returns an `Ecto.DateTime` from an Erlang datetime tuple.
  """
  def from_erl({{year, month, day}, {hour, min, sec}}) do
    %Ecto.DateTime{year: year, month: month, day: day, hour: hour, min: min, sec: sec}
  end

  defp erl_load({{year, month, day}, {hour, min, sec}}) do
    %Ecto.DateTime{year: year, month: month, day: day,
                   hour: hour, min: min, sec: sec}
  end
end

defimpl String.Chars, for: [Ecto.DateTime, Ecto.Date, Ecto.Time] do
  def to_string(dt) do
    @for.to_string(dt)
  end
end

defimpl Inspect, for: [Ecto.DateTime, Ecto.Date, Ecto.Time] do
  @inspected inspect(@for)

  def inspect(dt, _opts) do
    "#" <> @inspected <> "<" <> @for.to_iso8601(dt) <> ">"
  end
end
