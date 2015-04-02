if Code.ensure_loaded?(Postgrex.Connection) do

  defmodule Ecto.Adapters.Postgres.DateTime do
    @moduledoc false

    alias Postgrex.TypeInfo
    @behaviour Postgrex.Extension

    @gd_epoch :calendar.date_to_gregorian_days({2000, 1, 1})
    @gs_epoch :calendar.datetime_to_gregorian_seconds({{2000, 1, 1}, {0, 0, 0}})

    @date_max_year 5874897
    @timestamp_max_year 294276

    def init(_parameters, _opts),
      do: :ok

    def matching(_),
      do: [send: "date_send", send: "time_send",
           send: "timestamp_send", send: "timestamptz_send"]

    def format(_),
      do: :binary

    ### ENCODING ###

    def encode(%TypeInfo{send: "date_send"}, date, _, _),
      do: encode_date(date)
    def encode(%TypeInfo{send: "time_send"}, time, _, _),
      do: encode_time(time)
    def encode(%TypeInfo{send: "timestamp_send"}, timestamp, _, _),
      do: encode_timestamp(timestamp)
    def encode(%TypeInfo{send: "timestamptz_send"}, timestamp, _, _),
      do: encode_timestamp(timestamp)

    defp encode_date({year, month, day}) when year <= @date_max_year do
      date = {year, month, day}
      <<:calendar.date_to_gregorian_days(date) - @gd_epoch :: signed-32>>
    end

    defp encode_time({hour, min, sec, usec})
        when hour in 0..23 and min in 0..59 and sec in 0..59 and usec in 0..999_999 do
      time = {hour, min, sec}
      <<:calendar.time_to_seconds(time) * 1_000_000 + usec :: signed-64>>
    end

    defp encode_timestamp({{year, month, day}, {hour, min, sec, usec}})
        when year <= @timestamp_max_year and hour in 0..23 and min in 0..59 and sec in 0..59 and usec in 0..999_999 do
      datetime = {{year, month, day}, {hour, min, sec}}
      secs = :calendar.datetime_to_gregorian_seconds(datetime) - @gs_epoch
      <<secs * 1_000_000 + usec :: signed-64>>
    end

    ### DECODING ###

    def decode(%TypeInfo{send: "date_send"}, <<n :: signed-32>>, _, _),
      do: decode_date(n)
    def decode(%TypeInfo{send: "time_send"}, <<n :: signed-64>>, _, _),
      do: decode_time(n)
    def decode(%TypeInfo{send: "timestamp_send"}, <<n :: signed-64>>, _, _),
      do: decode_timestamp(n)
    def decode(%TypeInfo{send: "timestamptz_send"}, <<n :: signed-64>>, _, _),
      do: decode_timestamp(n)

    defp decode_date(days) do
      :calendar.gregorian_days_to_date(days + @gd_epoch)
    end

    defp decode_time(microsecs) do
      secs = div(microsecs, 1_000_000)
      msec = rem(microsecs, 1_000_000)
      {hour, min, sec} = :calendar.seconds_to_time(secs)
      {hour, min, sec, msec}
    end

    defp decode_timestamp(microsecs) do
      secs = div(microsecs, 1_000_000)
      msec = rem(microsecs, 1_000_000)
      {{year, month, day}, {hour, min, sec}} = :calendar.gregorian_seconds_to_datetime(secs + @gs_epoch)

      if year < 2000 and msec != 0 do
        sec = sec - 1
        msec = 1_000_000 + msec
      end

      {{year, month, day}, {hour, min, sec, msec}}
    end
  end

end
