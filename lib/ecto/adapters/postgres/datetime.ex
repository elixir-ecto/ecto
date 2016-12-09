if Code.ensure_loaded?(Postgrex) do
  defmodule Ecto.Adapters.Postgres.Time do
    @moduledoc false
    import Postgrex.BinaryUtils, warn: false
    use Postgrex.BinaryExtension, [send: "time_send"]

    def init(opts), do: opts

    def encode(_) do
      quote location: :keep do
        {hour, min, sec, usec} when hour in 0..23 and min in 0..59 and sec in 0..59 and usec in 0..999_999 ->
          time = {hour, min, sec}
          <<8 :: int32, :calendar.time_to_seconds(time) * 1_000_000 + usec :: int64>>
      end
    end

    def decode(_) do
      quote location: :keep do
        <<8 :: int32, microsecs :: int64>> ->
          secs = div(microsecs, 1_000_000)
          usec = rem(microsecs, 1_000_000)
          {hour, min, sec} = :calendar.seconds_to_time(secs)
          {hour, min, sec, usec}
      end
    end
  end

  defmodule Ecto.Adapters.Postgres.Date do
    @moduledoc false
    import Postgrex.BinaryUtils, warn: false
    use Postgrex.BinaryExtension, send: "date_send"

    @gd_epoch :calendar.date_to_gregorian_days({2000, 1, 1})
    @max_year 5874897

    def init(opts), do: opts

    def encode(_) do
      quote location: :keep do
        {year, month, day} when year <= unquote(@max_year) ->
          date = {year, month, day}
          <<4 :: int32, :calendar.date_to_gregorian_days(date) - unquote(@gd_epoch) :: int32>>
      end
    end

    def decode(_) do
      quote location: :keep do
        <<4 :: int32, days :: int32>> ->
          :calendar.gregorian_days_to_date(days + unquote(@gd_epoch))
      end
    end
  end

  defmodule Ecto.Adapters.Postgres.Timestamp do
    @moduledoc false
    import Postgrex.BinaryUtils, warn: false
    use Postgrex.BinaryExtension, [send: "timestamp_send"]

    @gs_epoch :calendar.datetime_to_gregorian_seconds({{2000, 1, 1}, {0, 0, 0}})
    @max_year 294276

    def init(opts), do: opts

    def encode(_) do
      quote location: :keep do
        timestamp ->
          Ecto.Adapters.Postgres.Timestamp.encode!(timestamp)
      end
    end

    def decode(_) do
      quote location: :keep do
        <<8 :: int32, microsecs :: int64>> ->
          Ecto.Adapters.Postgres.Timestamp.decode!(microsecs)
      end
    end

    ## Helpers

    def encode!({{year, month, day}, {hour, min, sec, usec}})
        when year <= @max_year and hour in 0..23 and min in 0..59 and sec in 0..59 and usec in 0..999_999 do
      datetime = {{year, month, day}, {hour, min, sec}}
      secs = :calendar.datetime_to_gregorian_seconds(datetime) - @gs_epoch
      <<8 :: int32, secs * 1_000_000 + usec :: int64>>
    end

    def encode!(arg) do
      raise ArgumentError, """
      could not encode date/time: #{inspect arg}

      This error happens when you are by-passing Ecto's Query API by
      using either Ecto.Adapters.SQL.query/4 or Ecto fragments. This
      makes Ecto unable to properly cast the type. You can fix this by
      explicitly telling Ecto which type to use via `type/2` or by
      implementing the Ecto.DataType protocol for the given value.
      """
    end

    def decode!(microsecs) when microsecs < 0 and rem(microsecs, 1_000_000) != 0 do
      secs = div(microsecs, 1_000_000) - 1
      microsecs = 1_000_000 + rem(microsecs, 1_000_000)
      split(secs, microsecs)
    end
    def decode!(microsecs) do
      secs = div(microsecs, 1_000_000)
      microsecs = rem(microsecs, 1_000_000)
      split(secs, microsecs)
    end

    defp split(secs, microsecs) do
      {date, {hour, min, sec}} = :calendar.gregorian_seconds_to_datetime(secs + @gs_epoch)
      {date, {hour, min, sec, microsecs}}
    end
  end

  defmodule Ecto.Adapters.Postgres.TimestampTZ do
    @moduledoc false
    import Postgrex.BinaryUtils, warn: false
    use Postgrex.BinaryExtension, [send: "timestamptz_send"]

    def init(opts), do: opts

    def encode(_) do
      quote location: :keep do
        timestamp ->
          Ecto.Adapters.Postgres.Timestamp.encode!(timestamp)
      end
    end

    def decode(_) do
      quote location: :keep do
        <<8 :: int32, microsecs :: int64>> ->
          Ecto.Adapters.Postgres.Timestamp.decode!(microsecs)
      end
    end
  end
end
