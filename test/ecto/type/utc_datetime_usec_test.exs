defmodule Ecto.Type.UTCDateTimeUsecTest do
  use ExUnit.Case, async: true

  import Ecto.Type.UTCDateTimeUsec

  @datetime DateTime.from_unix!(1_422_057_007, :second)
  @datetime_zero DateTime.from_unix!(1_422_057_000, :second)
  @datetime_zero_usec DateTime.from_unix!(1_422_057_000_000_000, :microsecond)
  @datetime_usec DateTime.from_unix!(1_422_057_007_008_000, :microsecond)
  @datetime_leapyear_usec DateTime.from_unix!(951_868_207_008_000, :microsecond)

  test "cast/1" do
    assert cast(@datetime_zero) == {:ok, @datetime_zero_usec}
    assert cast(@datetime_usec) == {:ok, @datetime_usec}

    assert cast("2015-01-23 23:50:00") == {:ok, @datetime_zero_usec}
    assert cast("2015-01-23T23:50:00") == {:ok, @datetime_zero_usec}
    assert cast("2015-01-23T23:50:00Z") == {:ok, @datetime_zero_usec}
    assert cast("2015-01-24T09:50:00+10:00") == {:ok, @datetime_zero_usec}
    assert cast("2015-01-23T23:50:07.008000") == {:ok, @datetime_usec}
    assert cast("2015-01-23T23:50:07.008000Z") == {:ok, @datetime_usec}
    assert cast("2015-01-23T17:50:07.008000-06:00") == {:ok, @datetime_usec}
    assert cast("2000-02-29T23:50:07.008") == {:ok, @datetime_leapyear_usec}
    assert cast("2015-01-23P23:50:07") == :error

    assert cast(%DateTime{
             calendar: Calendar.ISO,
             year: 2015,
             month: 1,
             day: 24,
             hour: 9,
             minute: 50,
             second: 0,
             microsecond: {0, 0},
             std_offset: 0,
             utc_offset: 36000,
             time_zone: "Etc/GMT-10",
             zone_abbr: "+10"
           }) == {:ok, @datetime_zero_usec}

    assert cast(%{
             "year" => "2015",
             "month" => "1",
             "day" => "23",
             "hour" => "23",
             "minute" => "50",
             "second" => "00"
           }) == {:ok, @datetime_zero_usec}

    assert cast(%{year: 2015, month: 1, day: 23, hour: 23, minute: 50, second: 0}) ==
             {:ok, @datetime_zero_usec}

    assert cast(%{"year" => "", "month" => "", "day" => "", "hour" => "", "minute" => ""}) ==
             {:ok, nil}

    assert cast(%{year: nil, month: nil, day: nil, hour: nil, minute: nil}) == {:ok, nil}

    assert cast(%{
             "year" => "2015",
             "month" => "1",
             "day" => "23",
             "hour" => "23",
             "minute" => "50"
           }) == {:ok, @datetime_zero_usec}

    assert cast(%{year: 2015, month: 1, day: 23, hour: 23, minute: 50}) ==
             {:ok, @datetime_zero_usec}

    assert cast(%{
             year: 2015,
             month: 1,
             day: 23,
             hour: 23,
             minute: 50,
             second: 07,
             microsecond: 8_000
           }) == {:ok, @datetime_usec}

    assert cast(%{
             "year" => 2015,
             "month" => 1,
             "day" => 23,
             "hour" => 23,
             "minute" => 50,
             "second" => 07,
             "microsecond" => 8_000
           }) == {:ok, @datetime_usec}

    assert cast(%{"year" => "2015", "month" => "1", "day" => "23", "hour" => "", "minute" => "50"}) ==
             :error

    assert cast(%{year: 2015, month: 1, day: 23, hour: 23, minute: nil}) == :error

    assert cast(~T[12:23:34]) == :error
    assert cast(1) == :error
  end

  test "dump/1" do
    assert dump(@datetime) == :error
    assert dump(@datetime_usec) == {:ok, ~N[2015-01-23 23:50:07.008000]}
  end

  test "load/1" do
    assert load(@datetime_usec) == {:ok, @datetime_usec}
    assert load(~N[2015-01-23 23:50:07.008000]) == {:ok, @datetime_usec}
    assert load(~N[2000-02-29 23:50:07.008000]) == {:ok, @datetime_leapyear_usec}
    assert load(@datetime_leapyear_usec) == {:ok, @datetime_leapyear_usec}
    assert load(@datetime_zero) == {:ok, @datetime_zero_usec}
    assert load(~D[2018-01-01]) == :error
  end
end
