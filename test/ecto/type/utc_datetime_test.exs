defmodule Ecto.Type.UTCDateTimeTest do
  use ExUnit.Case, async: true

  import Ecto.Type.UTCDateTime

  @datetime DateTime.from_unix!(1_422_057_007, :second)
  @datetime_zero DateTime.from_unix!(1_422_057_000, :second)
  @datetime_usec DateTime.from_unix!(1_422_057_007_008_000, :microsecond)
  @datetime_leapyear DateTime.from_unix!(951_868_207, :second)

  test "cast/1" do
    assert cast(@datetime) == {:ok, @datetime}
    assert cast(@datetime_usec) == {:ok, @datetime}
    assert cast(@datetime_leapyear) == {:ok, @datetime_leapyear}

    assert cast("2015-01-23 23:50:07") == {:ok, @datetime}
    assert cast("2015-01-23T23:50:07") == {:ok, @datetime}
    assert cast("2015-01-23T23:50:07Z") == {:ok, @datetime}
    assert cast("2015-01-24T09:50:07+10:00") == {:ok, @datetime}
    assert cast("2000-02-29T23:50:07") == {:ok, @datetime_leapyear}
    assert cast("2015-01-23P23:50:07") == :error

    assert cast("2015-01-23T23:50:07.008000") == {:ok, @datetime}
    assert cast("2015-01-23T23:50:07.008000Z") == {:ok, @datetime}
    assert cast("2015-01-23T17:50:07.008000-06:00") == {:ok, @datetime}

    assert cast(%{
             "year" => "2015",
             "month" => "1",
             "day" => "23",
             "hour" => "23",
             "minute" => "50",
             "second" => "07"
           }) == {:ok, @datetime}

    assert cast(%{year: 2015, month: 1, day: 23, hour: 23, minute: 50, second: 07}) ==
             {:ok, @datetime}

    assert cast(%DateTime{
             calendar: Calendar.ISO,
             year: 2015,
             month: 1,
             day: 24,
             hour: 9,
             minute: 50,
             second: 7,
             microsecond: {0, 0},
             std_offset: 0,
             utc_offset: 36000,
             time_zone: "Etc/GMT-10",
             zone_abbr: "+10"
           }) == {:ok, @datetime}

    assert cast(%{"year" => "", "month" => "", "day" => "", "hour" => "", "minute" => ""}) ==
             {:ok, nil}

    assert cast(%{year: nil, month: nil, day: nil, hour: nil, minute: nil}) == {:ok, nil}

    assert cast(%{
             "year" => "2015",
             "month" => "1",
             "day" => "23",
             "hour" => "23",
             "minute" => "50"
           }) == {:ok, @datetime_zero}

    assert cast(%{year: 2015, month: 1, day: 23, hour: 23, minute: 50}) == {:ok, @datetime_zero}

    assert cast(%{
             year: 2015,
             month: 1,
             day: 23,
             hour: 23,
             minute: 50,
             second: 07,
             microsecond: 8_000
           }) == {:ok, @datetime}

    assert cast(%{
             "year" => 2015,
             "month" => 1,
             "day" => 23,
             "hour" => 23,
             "minute" => 50,
             "second" => 07,
             "microsecond" => 8_000
           }) == {:ok, @datetime}

    assert cast(%{"year" => "2015", "month" => "1", "day" => "23", "hour" => "", "minute" => "50"}) ==
             :error

    assert cast(%{year: 2015, month: 1, day: 23, hour: 23, minute: nil}) == :error

    assert cast(~T[12:23:34]) == :error
    assert cast(1) == :error
  end

  test "dump/1" do
    assert dump(@datetime) == {:ok, ~N[2015-01-23 23:50:07]}
    assert dump(@datetime_zero) == {:ok, ~N[2015-01-23 23:50:00]}
    assert dump(@datetime_leapyear) == {:ok, ~N[2000-02-29 23:50:07]}
    assert dump(@datetime_usec) == :error
  end

  test "load/1" do
    assert load(~N[2015-01-23 23:50:07]) == {:ok, @datetime}
    assert load(~N[2015-01-23 23:50:00]) == {:ok, @datetime_zero}
    assert load(~N[2015-01-23 23:50:07.008000]) == {:ok, @datetime}
    assert load(~N[2000-02-29 23:50:07]) == {:ok, @datetime_leapyear}
    assert load(@datetime) == {:ok, @datetime}
    assert load(@datetime_zero) == {:ok, @datetime_zero}
    assert load(@datetime_usec) == {:ok, @datetime}
    assert load(@datetime_leapyear) == {:ok, @datetime_leapyear}
  end
end
