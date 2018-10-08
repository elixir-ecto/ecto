defmodule Ecto.Type.TimeUsecTest do
  use ExUnit.Case, async: true

  import Ecto.Type.TimeUsec

  @time ~T[23:50:07]
  @time_zero ~T[23:50:00]
  @time_zero_usec ~T[23:50:00.000000]
  @time_usec ~T[23:50:07.030000]

  test "cast/1" do
    assert cast(@time_usec) == {:ok, @time_usec}
    assert cast(@time_zero) == {:ok, @time_zero_usec}

    assert cast("23:50:00") == {:ok, @time_zero_usec}
    assert cast("23:50:00Z") == {:ok, @time_zero_usec}
    assert cast("23:50:07.03") == {:ok, @time_usec}
    assert cast("23:50:07.03Z") == {:ok, @time_usec}
    assert cast("23:50:07.030000") == {:ok, @time_usec}
    assert cast("23:50:07.030000Z") == {:ok, @time_usec}
    assert cast("24:01:01") == :error
    assert cast("00:61:00") == :error
    assert cast("00:00:61") == :error
    assert cast("00:00:009") == :error
    assert cast("00:00:00.A00") == :error

    assert cast(%{"hour" => "23", "minute" => "50", "second" => "00"}) == {:ok, @time_zero_usec}
    assert cast(%{hour: 23, minute: 50, second: 0}) == {:ok, @time_zero_usec}
    assert cast(%{"hour" => "", "minute" => ""}) == {:ok, nil}
    assert cast(%{hour: nil, minute: nil}) == {:ok, nil}
    assert cast(%{"hour" => "23", "minute" => "50"}) == {:ok, @time_zero_usec}
    assert cast(%{hour: 23, minute: 50}) == {:ok, @time_zero_usec}
    assert cast(%{hour: 23, minute: 50, second: 07, microsecond: 30_000}) == {:ok, @time_usec}

    assert cast(%{"hour" => 23, "minute" => 50, "second" => 07, "microsecond" => 30_000}) ==
             {:ok, @time_usec}

    assert cast(%{"hour" => "", "minute" => "50"}) == :error
    assert cast(%{hour: 23, minute: nil}) == :error

    assert cast(~N[2016-11-11 23:30:10]) == {:ok, ~T[23:30:10.000000]}

    utc_datetime = DateTime.from_naive!(~N[2016-11-11 23:30:10], "Etc/UTC")
    assert cast(utc_datetime) == {:ok, ~T[23:30:10.000000]}

    assert cast(~D[2016-11-11]) == :error
  end

  test "dump/1" do
    assert dump(@time_usec) == {:ok, @time_usec}
    assert dump(@time) == :error
  end

  test "load/1" do
    assert load(@time_usec) == {:ok, @time_usec}
    assert load(@time_zero) == {:ok, @time_zero_usec}
  end
end
