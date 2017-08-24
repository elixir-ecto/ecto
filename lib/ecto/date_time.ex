# TODO: Remove Ecto.Date|Time types on Ecto v2.3
import Kernel, except: [to_string: 1]

defmodule Ecto.DateTime.Utils do
  @moduledoc false

  @doc "Pads with zero"
  def zero_pad(val, count) do
    num = Integer.to_string(val)
    pad_length = max(count - byte_size(num), 0)
    :binary.copy("0", pad_length) <> num
  end

  @doc "Converts to integer if possible"
  def to_i(nil), do: nil
  def to_i({int, _}) when is_integer(int), do: int
  def to_i(int) when is_integer(int), do: int
  def to_i(bin) when is_binary(bin) do
    case Integer.parse(bin) do
      {int, ""} -> int
      _ -> nil
    end
  end

  @doc "A guard to check for dates"
  defmacro is_date(year, month, day) do
    quote do
      is_integer(unquote(year)) and unquote(month) in 1..12 and unquote(day) in 1..31
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
      {int, rest} when byte_size(int) > 6 and is_iso_8601(rest) ->
        String.to_integer(binary_part(int, 0, 6))
      {int, rest} when byte_size(int) in 1..6 and is_iso_8601(rest) ->
        pad = String.duplicate("0", 6 - byte_size(int))
        String.to_integer(int <> pad)
      _ ->
        nil
    end
  end
  def usec(rest) when is_iso_8601(rest), do: 0
  def usec(_), do: nil

  @doc """
  Compare two datetimes.

  Receives two datetimes and compares the `t1`
  against `t2` and returns `:lt`, `:eq` or `:gt`.
  """
  def compare(%{__struct__: module} = t1, %{__struct__: module} = t2) do
    {:ok, t1} = module.dump(t1)
    {:ok, t2} = module.dump(t2)
    cond do
      t1 == t2 -> :eq
      t1 > t2 -> :gt
      true -> :lt
    end
  end

  defp parse(<<h, t::binary>>, acc) when h in ?0..?9, do: parse(t, <<acc::binary, h>>)
  defp parse(rest, acc), do: {acc, rest}
end

defmodule Ecto.Date do
  @moduledoc """
  A deprecated Ecto type for dates.

  This type is deprecated in favour of the `:date` type.
  """

  @behaviour Ecto.Type
  defstruct [:year, :month, :day]

  import Ecto.DateTime.Utils

  @doc """
  Compare two dates.

  Receives two dates and compares the `t1`
  against `t2` and returns `:lt`, `:eq` or `:gt`.
  """
  defdelegate compare(t1, t2), to: Ecto.DateTime.Utils

  @doc """
  The Ecto primitive type.
  """
  def type, do: :date

  @doc """
  Casts the given value to date.

  It supports:

    * a binary in the "YYYY-MM-DD" format
    * a binary in the "YYYY-MM-DD HH:MM:SS" format
      (may be separated by T and/or followed by "Z", as in `2014-04-17T14:00:00Z`)
    * a binary in the "YYYY-MM-DD HH:MM:SS.USEC" format
      (may be separated by T and/or followed by "Z", as in `2014-04-17T14:00:00.030Z`)
    * a map with `"year"`, `"month"` and `"day"` keys
      with integer or binaries as values
    * a map with `:year`, `:month` and `:day` keys
      with integer or binaries as values
    * a tuple with `{year, month, day}` as integers or binaries
    * an `Ecto.Date` struct itself

  """
  def cast(d), do: d |> do_cast() |> validate_cast()

  @doc """
  Same as `cast/1` but raises `Ecto.CastError` on invalid dates.
  """
  def cast!(value) do
    case cast(value) do
      {:ok, date} -> date
      :error -> raise Ecto.CastError, type: __MODULE__, value: value
    end
  end

  defp do_cast(<<year::4-bytes, ?-, month::2-bytes, ?-, day::2-bytes>>),
    do: from_parts(to_i(year), to_i(month), to_i(day))
  defp do_cast(<<year::4-bytes, ?-, month::2-bytes, ?-, day::2-bytes, sep,
             _hour::2-bytes, ?:, _min::2-bytes, ?:, _sec::2-bytes, _rest::binary>>) when sep in [?\s, ?T],
    do: from_parts(to_i(year), to_i(month), to_i(day))
  defp do_cast(%Ecto.Date{} = d),
    do: {:ok, d}
  defp do_cast(%{"year" => empty, "month" => empty, "day" => empty}) when empty in ["", nil],
    do: {:ok, nil}
  defp do_cast(%{year: empty, month: empty, day: empty}) when empty in ["", nil],
    do: {:ok, nil}
  defp do_cast(%{"year" => year, "month" => month, "day" => day}),
    do: from_parts(to_i(year), to_i(month), to_i(day))
  defp do_cast(%{year: year, month: month, day: day}),
    do: from_parts(to_i(year), to_i(month), to_i(day))
  defp do_cast({year, month, day}),
    do: from_parts(to_i(year), to_i(month), to_i(day))
  defp do_cast(_),
    do: :error

  defp validate_cast(:error), do: :error
  defp validate_cast({:ok, nil}), do: {:ok, nil}
  defp validate_cast({:ok, %{year: y, month: m, day: d} = date}) do
    if :calendar.valid_date(y, m, d), do: {:ok, date}, else: :error
  end

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
  def dump(_), do: :error

  @doc """
  Converts a date triplet into an `Ecto.Date`.
  """
  def load({year, month, day}) do
    {:ok, %Ecto.Date{year: year, month: month, day: day}}
  end
  def load(_), do: :error

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
  Returns an `Ecto.Date` in UTC.
  """
  def utc do
    {{year, month, day}, _time} = :erlang.universaltime
    %Ecto.Date{year: year, month: month, day: day}
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
end

defmodule Ecto.Time do
  @moduledoc """
  A deprecated Ecto type for time.

  This type is deprecated in favour of the `:time` type.
  """

  @behaviour Ecto.Type
  defstruct [:hour, :min, :sec, usec: 0]

  import Ecto.DateTime.Utils

  @doc """
  Compare two times.

  Receives two times and compares the `t1`
  against `t2` and returns `:lt`, `:eq` or `:gt`.
  """
  defdelegate compare(t1, t2), to: Ecto.DateTime.Utils

  @doc """
  The Ecto primitive type.
  """
  def type, do: :time

  @doc """
  Casts the given value to time.

  It supports:

    * a binary in the "HH:MM:SS" format
      (may be followed by "Z", as in `12:00:00Z`)
    * a binary in the "HH:MM:SS.USEC" format
      (may be followed by "Z", as in `12:00:00.005Z`)
    * a map with `"hour"`, `"minute"` keys with `"second"` and `"microsecond"`
      as optional keys and values are integers or binaries
    * a map with `:hour`, `:minute` keys with `:second` and `:microsecond`
      as optional keys and values are integers or binaries
    * a tuple with `{hour, min, sec}` as integers or binaries
    * a tuple with `{hour, min, sec, usec}` as integers or binaries
    * an `Ecto.Time` struct itself

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

  def cast(%{"hour" => empty, "minute" => empty}) when empty in ["", nil],
    do: {:ok, nil}
  def cast(%{hour: empty, minute: empty}) when empty in ["", nil],
    do: {:ok, nil}

  def cast(%{"hour" => hour, "minute" => minute} = map),
    do: from_parts(to_i(hour), to_i(minute), to_i(Map.get(map, "second", 0)), to_i(Map.get(map, "microsecond", 0)))
  def cast(%{hour: hour, minute: minute} = map),
    do: from_parts(to_i(hour), to_i(minute), to_i(Map.get(map, :second, 0)), to_i(Map.get(map, :microsecond, 0)))

  def cast({hour, min, sec}),
    do: from_parts(to_i(hour), to_i(min), to_i(sec), 0)
  def cast({hour, min, sec, usec}),
    do: from_parts(to_i(hour), to_i(min), to_i(sec), to_i(usec))
  def cast(_),
    do: :error

  @doc """
  Same as `cast/1` but raises `Ecto.CastError` on invalid times.
  """
  def cast!(value) do
    case cast(value) do
      {:ok, time} -> time
      :error -> raise Ecto.CastError, type: __MODULE__, value: value
    end
  end

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
  def dump(_), do: :error

  @doc """
  Converts a time tuple like the one returned by `dump/1` into an `Ecto.Time`.
  """
  def load({hour, min, sec, usec}) do
    {:ok, %Ecto.Time{hour: hour, min: min, sec: sec, usec: usec}}
  end
  def load({_, _, _} = time) do
    {:ok, from_erl(time)}
  end
  def load(_), do: :error

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
  Converts `Ecto.Time` to its ISO 8601 representation.
  """
  def to_iso8601(time) do
    to_string(time)
  end

  @doc """
  Returns an `Ecto.Time` in UTC.

  `precision` can be `:sec` or `:usec.`
  """
  def utc(precision \\ :sec)

  def utc(:sec) do
    {_, {hour, min, sec}} = :erlang.universaltime
    %Ecto.Time{hour: hour, min: min, sec: sec}
  end

  def utc(:usec) do
    now = {_, _, usec} = :os.timestamp
    {_date, {hour, min, sec}} = :calendar.now_to_universal_time(now)
    %Ecto.Time{hour: hour, min: min, sec: sec, usec: usec}
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
end

defmodule Ecto.DateTime do
  @moduledoc """
  A deprecated Ecto type that includes a date and a time.

  This type is deprecated in favour of the `:naive_datetime` type.
  """

  @behaviour Ecto.Type
  defstruct [:year, :month, :day, :hour, :min, :sec, usec: 0]

  import Ecto.DateTime.Utils

  @unix_epoch :calendar.datetime_to_gregorian_seconds {{1970, 1, 1}, {0, 0, 0}}

  @doc """
  Compare two datetimes.

  Receives two datetimes and compares the `t1`
  against `t2` and returns `:lt`, `:eq` or `:gt`.
  """
  defdelegate compare(t1, t2), to: Ecto.DateTime.Utils

  @doc """
  The Ecto primitive type.
  """
  def type, do: :naive_datetime

  @doc """
  Casts the given value to datetime.

  It supports:

    * a binary in the "YYYY-MM-DD HH:MM:SS" format
      (may be separated by T and/or followed by "Z", as in `2014-04-17T14:00:00Z`)
    * a binary in the "YYYY-MM-DD HH:MM:SS.USEC" format
      (may be separated by T and/or followed by "Z", as in `2014-04-17T14:00:00.030Z`)
    * a map with `"year"`, `"month"`,`"day"`, `"hour"`, `"minute"` keys
      with `"second"` and `"microsecond"` as optional keys and values are integers or binaries
    * a map with `:year`, `:month`,`:day`, `:hour`, `:minute` keys
      with `:second` and `:microsecond` as optional keys and values are integers or binaries
    * a tuple with `{{year, month, day}, {hour, min, sec}}` as integers or binaries
    * a tuple with `{{year, month, day}, {hour, min, sec, usec}}` as integers or binaries
    * an `Ecto.DateTime` struct itself

  """
  def cast(dt), do: dt |> do_cast() |> validate_cast()

  @doc """
  Same as `cast/1` but raises `Ecto.CastError` on invalid datetimes.
  """
  def cast!(value) do
    case cast(value) do
      {:ok, datetime} -> datetime
      :error -> raise Ecto.CastError, type: __MODULE__, value: value
    end
  end

  defp do_cast(<<year::4-bytes, ?-, month::2-bytes, ?-, day::2-bytes, sep,
             hour::2-bytes, ?:, min::2-bytes, ?:, sec::2-bytes, rest::binary>>) when sep in [?\s, ?T] do
    if usec = usec(rest) do
      from_parts(to_i(year), to_i(month), to_i(day),
                 to_i(hour), to_i(min), to_i(sec), usec)
    else
      :error
    end
  end

  defp do_cast(%Ecto.DateTime{} = dt) do
    {:ok, dt}
  end

  defp do_cast(%{"year" => year, "month" => month, "day" => day, "hour" => hour, "min" => min} = map) do
    from_parts(to_i(year), to_i(month), to_i(day),
               to_i(hour), to_i(min), to_i(Map.get(map, "sec", 0)),
               to_i(Map.get(map, "usec", 0)))
  end

  defp do_cast(%{year: year, month: month, day: day, hour: hour, min: min} = map) do
    from_parts(to_i(year), to_i(month), to_i(day),
               to_i(hour), to_i(min), to_i(Map.get(map, :sec, 0)),
               to_i(Map.get(map, :usec, 0)))
  end

  defp do_cast(%{"year" => empty, "month" => empty, "day" => empty,
                 "hour" => empty, "minute" => empty}) when empty in ["", nil] do
    {:ok, nil}
  end

  defp do_cast(%{year: empty, month: empty, day: empty,
                 hour: empty, minute: empty}) when empty in ["", nil] do
    {:ok, nil}
  end

  defp do_cast(%{"year" => year, "month" => month, "day" => day, "hour" => hour, "minute" => min} = map) do
    from_parts(to_i(year), to_i(month), to_i(day),
               to_i(hour), to_i(min), to_i(Map.get(map, "second", 0)),
               to_i(Map.get(map, "microsecond", 0)))
  end

  defp do_cast(%{year: year, month: month, day: day, hour: hour, minute: min} = map) do
    from_parts(to_i(year), to_i(month), to_i(day),
               to_i(hour), to_i(min), to_i(Map.get(map, :second, 0)),
               to_i(Map.get(map, :microsecond, 0)))
  end

  defp do_cast({{year, month, day}, {hour, min, sec}}) do
    from_parts(to_i(year), to_i(month), to_i(day),
               to_i(hour), to_i(min), to_i(sec), 0)
  end

  defp do_cast({{year, month, day}, {hour, min, sec, usec}}) do
    from_parts(to_i(year), to_i(month), to_i(day),
               to_i(hour), to_i(min), to_i(sec), to_i(usec))
  end

  defp do_cast(_) do
    :error
  end

  defp validate_cast(:error), do: :error
  defp validate_cast({:ok, nil}), do: {:ok, nil}
  defp validate_cast({:ok, %{year: y, month: m, day: d} = datetime}) do
    if :calendar.valid_date(y, m, d), do: {:ok, datetime}, else: :error
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
  def dump(_), do: :error

  @doc """
  Converts a `{date, time}` tuple into an `Ecto.DateTime`.
  """
  def load({{_, _, _}, {_, _, _, _}} = datetime) do
    {:ok, erl_load(datetime)}
  end
  def load({{_, _, _}, {_, _, _}} = datetime) do
    {:ok, from_erl(datetime)}
  end
  def load(_), do: :error

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
  Converts the given `Ecto.Date` into `Ecto.DateTime` with the time being
  00:00:00.
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
  Converts `Ecto.DateTime` to its ISO 8601 representation
  without timezone specification.
  """
  def to_iso8601(%Ecto.DateTime{year: year, month: month, day: day,
                                hour: hour, min: min, sec: sec, usec: usec}) do
    str = zero_pad(year, 4) <> "-" <> zero_pad(month, 2) <> "-" <> zero_pad(day, 2) <> "T" <>
          zero_pad(hour, 2) <> ":" <> zero_pad(min, 2) <> ":" <> zero_pad(sec, 2)

    if is_nil(usec) or usec == 0 do
      str
    else
      str <> "." <> zero_pad(usec, 6)
    end
  end

  @doc """
  Returns an `Ecto.DateTime` in UTC.

  `precision` can be `:sec` or `:usec`.
  """
  def utc(precision \\ :sec) do
    autogenerate(precision)
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
    %Ecto.DateTime{year: year, month: month, day: day,
                   hour: hour, min: min, sec: sec}
  end

  def from_unix!(integer, unit) do
    total = System.convert_time_unit(integer, unit, :microseconds)
    microsecond = rem(total, 1_000_000)
    {{year, month, day}, {hour, minute, second}} =
      :calendar.gregorian_seconds_to_datetime(@unix_epoch + div(total, 1_000_000))
    %Ecto.DateTime{year: year, month: month, day: day,
                      hour: hour, min: minute, sec: second, usec: microsecond}
  end

  # Callback invoked by autogenerate fields.
  @doc false
  def autogenerate(precision \\ :sec)

  def autogenerate(:sec) do
    {date, {h, m, s}} = :erlang.universaltime
    erl_load({date, {h, m, s, 0}})
  end

  def autogenerate(:usec) do
    timestamp = {_, _, usec} = :os.timestamp
    {date, {h, m, s}} = :calendar.now_to_datetime(timestamp)
    erl_load({date, {h, m, s, usec}})
  end

  defp erl_load({{year, month, day}, {hour, min, sec, usec}}) do
    %Ecto.DateTime{year: year, month: month, day: day,
                   hour: hour, min: min, sec: sec, usec: usec}
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
    "#" <> @inspected <> "<" <> @for.to_string(dt) <> ">"
  end
end

defimpl Ecto.DataType, for: Ecto.DateTime do
  def dump(%Ecto.DateTime{year: year, month: month, day: day,
                          hour: hour, min: min, sec: sec, usec: usec}) do
    {:ok, {{year, month, day}, {hour, min, sec, usec}}}
  end
end

defimpl Ecto.DataType, for: Ecto.Date do
  def dump(%Ecto.Date{year: year, month: month, day: day}) do
    {:ok, {year, month, day}}
  end
end

defimpl Ecto.DataType, for: Ecto.Time do
  def dump(%Ecto.Time{hour: hour, min: min, sec: sec, usec: usec}) do
    {:ok, {hour, min, sec, usec}}
  end
end

if Code.ensure_loaded?(Poison) do
  defimpl Poison.Encoder, for: [Ecto.Date, Ecto.Time, Ecto.DateTime] do
    def encode(dt, _opts), do: <<?", @for.to_iso8601(dt)::binary, ?">>
  end
end
