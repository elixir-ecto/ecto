defmodule Ecto.Type.NaiveDateTimeTest do
  use ExUnit.Case, async: true

  import Ecto.Type.NaiveDateTime

  @datetime ~N[2015-01-23 23:50:07]
  @datetime_zero ~N[2015-01-23 23:50:00]
  @datetime_usec ~N[2015-01-23 23:50:07.008000]
  @datetime_leapyear ~N[2000-02-29 23:50:07]

  test "cast/1" do
    assert cast(@datetime) == {:ok, @datetime}
    assert cast(@datetime_usec) == {:ok, @datetime}
    assert cast(@datetime_leapyear) == {:ok, @datetime_leapyear}

    assert cast("2015-01-23 23:50:07") == {:ok, @datetime}
    assert cast("2015-01-23T23:50:07") == {:ok, @datetime}
    assert cast("2015-01-23T23:50:07Z") == {:ok, @datetime}
    assert cast("2000-02-29T23:50:07") == {:ok, @datetime_leapyear}
    assert cast("2015-01-23P23:50:07") == :error

    assert cast("2015-01-23T23:50:07.008000") == {:ok, @datetime}
    assert cast("2015-01-23T23:50:07.008000Z") == {:ok, @datetime}

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

    assert cast(DateTime.from_unix!(10, :second)) == {:ok, ~N[1970-01-01 00:00:10]}

    assert cast(~T[23:50:07]) == :error
    assert cast(1) == :error
  end

  test "dump/1" do
    assert dump(@datetime) == {:ok, @datetime}
    assert dump(@datetime_zero) == {:ok, @datetime_zero}
    assert dump(@datetime_leapyear) == {:ok, @datetime_leapyear}
    assert dump(@datetime_usec) == :error
  end

  test "load/1" do
    assert load(@datetime) == {:ok, @datetime}
    assert load(@datetime_zero) == {:ok, @datetime_zero}
    assert load(@datetime_usec) == {:ok, @datetime}
    assert load(@datetime_leapyear) == {:ok, @datetime_leapyear}
  end
end
