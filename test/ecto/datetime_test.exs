defmodule Ecto.DateTest do
  use ExUnit.Case, async: true

  @test_date "2015-12-31"
  @test_ecto_date %Ecto.Date{year: 2015, month: 12, day: 31}

  test "cast itself" do
    assert Ecto.Date.cast(@test_ecto_date) == {:ok, @test_ecto_date}
  end

  test "cast strings" do
    assert Ecto.Date.cast(@test_date) == {:ok, @test_ecto_date}
    assert Ecto.Date.cast("2015-00-23") == :error
    assert Ecto.Date.cast("2015-13-23") == :error
    assert Ecto.Date.cast("2015-01-00") == :error
    assert Ecto.Date.cast("2015-01-32") == :error
  end

  test "cast maps" do
    assert Ecto.Date.cast(%{"year" => "2015", "month" => "12", "day" => "31"}) ==
           {:ok, @test_ecto_date}
    assert Ecto.Date.cast(%{year: 2015, month: 12, day: 31}) ==
           {:ok, @test_ecto_date}
    assert Ecto.Date.cast(%{"year" => "2015", "month" => "", "day" => "31"}) ==
           :error
    assert Ecto.Date.cast(%{"year" => "2015", "month" => nil, "day" => "31"}) ==
           :error
    assert Ecto.Date.cast(%{"year" => "2015", "month" => nil}) ==
           :error
  end

  test "to_string" do
    assert to_string(@test_ecto_date) == @test_date
    assert Ecto.Date.to_string(@test_ecto_date) == @test_date
  end
end

defmodule Ecto.TimeTest do
  use ExUnit.Case, async: true

  @test_time "23:50:07"
  @test_ecto_time %Ecto.Time{hour: 23, min: 50, sec: 07, usec: 0}
  @test_ecto_time_zero %Ecto.Time{hour: 23, min: 50, sec: 0, usec: 0}

  @test_usec_time "12:40:33.030"
  @test_ecto_usec_time %Ecto.Time{hour: 12, min: 40, sec: 33, usec: 30_000}

  test "cast itself" do
    assert Ecto.Time.cast(@test_ecto_time) == {:ok, @test_ecto_time}
    assert Ecto.Time.cast(@test_ecto_time_zero) ==  {:ok, @test_ecto_time_zero}
  end

  test "cast strings" do
    assert Ecto.Time.cast(@test_time) == {:ok, @test_ecto_time}
    assert Ecto.Time.cast(@test_time <> "Z") == {:ok, @test_ecto_time}
    assert Ecto.Time.cast(@test_usec_time) == {:ok, @test_ecto_usec_time}
    assert Ecto.Time.cast(@test_usec_time <> "Z") == {:ok, @test_ecto_usec_time}
    assert Ecto.Time.cast(@test_time <> ".123456")
      == {:ok, %{@test_ecto_time | usec: 123456}}
    assert Ecto.Time.cast(@test_time <> ".123456Z")
      == {:ok, %{@test_ecto_time | usec: 123456}}
    assert Ecto.Time.cast(@test_time <> ".000123Z")
      == {:ok, %{@test_ecto_time | usec: 123}}

    assert Ecto.Date.cast("24:01:01") == :error
    assert Ecto.Date.cast("00:61:00") == :error
    assert Ecto.Date.cast("00:00:61") == :error
    assert Ecto.Date.cast("00:00:009") == :error
    assert Ecto.Date.cast("00:00:00.A00") == :error
  end

  test "cast maps" do
    assert Ecto.Time.cast(%{"hour" => "23", "min" => "50", "sec" => "07"}) ==
           {:ok, @test_ecto_time}
    assert Ecto.Time.cast(%{hour: 23, min: 50, sec: 07}) ==
           {:ok, @test_ecto_time}
    assert Ecto.Time.cast(%{"hour" => "23", "min" => "50"}) ==
           {:ok, @test_ecto_time_zero}
    assert Ecto.Time.cast(%{hour: 23, min: 50}) ==
           {:ok, @test_ecto_time_zero}
    assert Ecto.Time.cast(%{"hour" => "", "min" => "50"}) ==
           :error
    assert Ecto.Time.cast(%{hour: 23, min: nil}) ==
           :error
  end

  test "to_string" do
    assert to_string(@test_ecto_time) == @test_time
    assert Ecto.Time.to_string(@test_ecto_time) == @test_time

    assert to_string(@test_ecto_usec_time) == @test_usec_time <> "000"
    assert Ecto.Time.to_string(@test_ecto_usec_time) == @test_usec_time <> "000"

    assert to_string(%Ecto.Time{hour: 1, min: 2, sec: 3, usec: 4})
      == "01:02:03.000004"
    assert Ecto.Time.to_string(%Ecto.Time{hour: 1, min: 2, sec: 3, usec: 4})
      == "01:02:03.000004"
  end
end

defmodule Ecto.DateTimeTest do
  use ExUnit.Case, async: true

  @test_datetime "2015-01-23T23:50:07"
  @test_ecto_datetime %Ecto.DateTime{year: 2015, month: 1, day: 23, hour: 23, min: 50, sec: 07}
  @test_ecto_datetime_zero %Ecto.DateTime{year: 2015, month: 1, day: 23, hour: 23, min: 50, sec: 0}

  test "cast itself" do
    assert Ecto.DateTime.cast(@test_ecto_datetime) == {:ok, @test_ecto_datetime}
  end

  test "cast strings" do
    assert Ecto.DateTime.cast("2015-01-23 23:50:07") == {:ok, @test_ecto_datetime}
    assert Ecto.DateTime.cast("2015-01-23T23:50:07") == {:ok, @test_ecto_datetime}
    assert Ecto.DateTime.cast("2015-01-23T23:50:07Z") == {:ok, @test_ecto_datetime}
    assert Ecto.DateTime.cast("2015-01-23T23:50:07.000Z") == {:ok, @test_ecto_datetime}
    assert Ecto.DateTime.cast("2015-01-23P23:50:07") == :error
  end

  test "cast maps" do
    assert Ecto.DateTime.cast(%{"year" => "2015", "month" => "1", "day" => "23",
                                "hour" => "23", "min" => "50", "sec" => "07"}) ==
           {:ok, @test_ecto_datetime}

    assert Ecto.DateTime.cast(%{year: 2015, month: 1, day: 23, hour: 23, min: 50, sec: 07}) ==
           {:ok, @test_ecto_datetime}

    assert Ecto.DateTime.cast(%{"year" => "2015", "month" => "1", "day" => "23",
                                "hour" => "23", "min" => "50"}) ==
           {:ok, @test_ecto_datetime_zero}

    assert Ecto.DateTime.cast(%{year: 2015, month: 1, day: 23, hour: 23, min: 50}) ==
           {:ok, @test_ecto_datetime_zero}

    assert Ecto.DateTime.cast(%{"year" => "2015", "month" => "1", "day" => "23",
                                "hour" => "", "min" => "50"}) ==
           :error

    assert Ecto.DateTime.cast(%{year: 2015, month: 1, day: 23, hour: 23, min: nil}) ==
           :error
  end

  test "to_string" do
    assert to_string(@test_ecto_datetime) == @test_datetime <> "Z"
    assert Ecto.DateTime.to_string(@test_ecto_datetime) == @test_datetime <> "Z"
  end
end
