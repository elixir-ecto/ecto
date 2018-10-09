defmodule Ecto.Type.NaiveDateTimeUsecTest do
  use ExUnit.Case, async: true

  @datetime ~N[2015-01-23 23:50:07]
  @datetime_zero ~N[2015-01-23 23:50:00]
  @datetime_zero_usec ~N[2015-01-23 23:50:00.000000]
  @datetime_usec ~N[2015-01-23 23:50:07.008000]
  @datetime_leapyear ~N[2000-02-29 23:50:07]
  @datetime_leapyear_usec ~N[2000-02-29 23:50:07.000000]

  import Ecto.Type.NaiveDateTimeUsec

  describe "cast/1" do
    assert cast(@datetime_zero) == {:ok, @datetime_zero_usec}
    assert cast(@datetime_usec) == {:ok, @datetime_usec}
    assert cast(@datetime_leapyear) == {:ok, @datetime_leapyear_usec}

    assert cast("2015-01-23 23:50:00") == {:ok, @datetime_zero_usec}
    assert cast("2015-01-23T23:50:00") == {:ok, @datetime_zero_usec}
    assert cast("2015-01-23T23:50:00Z") == {:ok, @datetime_zero_usec}
    assert cast("2000-02-29T23:50:07") == {:ok, @datetime_leapyear_usec}
    assert cast("2015-01-23T23:50:07.008000") == {:ok, @datetime_usec}
    assert cast("2015-01-23T23:50:07.008000Z") == {:ok, @datetime_usec}
    assert cast("2015-01-23P23:50:07") == :error

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

    assert cast(DateTime.from_unix!(10, :second)) == {:ok, ~N[1970-01-01 00:00:10.000000]}

    assert cast(~T[23:50:07]) == :error
    assert cast(1) == :error
  end

  test "dump/1" do
    assert Ecto.Type.dump(:naive_datetime_usec, @datetime) == :error
    assert Ecto.Type.dump(:naive_datetime_usec, @datetime_zero) == :error
    assert Ecto.Type.dump(:naive_datetime_usec, @datetime_usec) == {:ok, @datetime_usec}

    assert Ecto.Type.dump(:naive_datetime_usec, @datetime_leapyear_usec) ==
             {:ok, @datetime_leapyear_usec}
  end

  test "load/1" do
    assert Ecto.Type.load(:naive_datetime_usec, @datetime_usec) == {:ok, @datetime_usec}

    assert Ecto.Type.load(:naive_datetime_usec, @datetime_leapyear_usec) ==
             {:ok, @datetime_leapyear_usec}
  end
end
