defmodule Ecto.Type.DateTest do
  use ExUnit.Case, async: true

  import Ecto.Type.Date

  @date ~D[2015-12-31]
  @leap_date ~D[2000-02-29]
  @date_unix_epoch ~D[1970-01-01]

  test "cast/1" do
    assert cast(@date) == {:ok, @date}

    assert cast("2015-12-31") == {:ok, @date}
    assert cast("2000-02-29") == {:ok, @leap_date}
    assert cast("2015-00-23") == :error
    assert cast("2015-13-23") == :error
    assert cast("2015-01-00") == :error
    assert cast("2015-01-32") == :error
    assert cast("2015-02-29") == :error
    assert cast("1900-02-29") == :error

    assert cast(%{"year" => "2015", "month" => "12", "day" => "31"}) == {:ok, @date}
    assert cast(%{year: 2015, month: 12, day: 31}) == {:ok, @date}
    assert cast(%{"year" => "", "month" => "", "day" => ""}) == {:ok, nil}
    assert cast(%{year: nil, month: nil, day: nil}) == {:ok, nil}
    assert cast(%{"year" => "2015", "month" => "", "day" => "31"}) == :error
    assert cast(%{"year" => "2015", "month" => nil, "day" => "31"}) == :error
    assert cast(%{"year" => "2015", "month" => nil}) == :error
    assert cast(%{"year" => "", "month" => "01", "day" => "30"}) == :error
    assert cast(%{"year" => nil, "month" => "01", "day" => "30"}) == :error

    assert cast(DateTime.from_unix!(10)) == {:ok, @date_unix_epoch}
    assert cast(~N[1970-01-01 12:23:34]) == {:ok, @date_unix_epoch}
    assert cast(@date) == {:ok, @date}
    assert cast(~T[12:23:34]) == :error

    assert cast("2015-12-31T00:00:00") == {:ok, @date}
    assert cast("2015-12-31 00:00:00") == {:ok, @date}
  end

  test "dump/1" do
    assert dump(@date) == {:ok, @date}
    assert dump(@leap_date) == {:ok, @leap_date}
    assert dump(@date_unix_epoch) == {:ok, @date_unix_epoch}
  end

  test "load/1" do
    assert load(@date) == {:ok, @date}
    assert load(@leap_date) == {:ok, @leap_date}
    assert load(@date_unix_epoch) == {:ok, @date_unix_epoch}
  end
end
