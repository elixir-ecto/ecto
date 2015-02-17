defmodule Ecto.DateTest do
  use ExUnit.Case, async: true

  @test_date "2015-12-31"
  @test_ecto_date %Ecto.Date{year: 2015, month: 12, day: 31}

  test "cast" do
    assert Ecto.Date.cast(@test_date) == {:ok, @test_ecto_date}
    assert Ecto.Date.cast("2015-00-23") == :error
    assert Ecto.Date.cast("2015-13-23") == :error
    assert Ecto.Date.cast("2015-01-00") == :error
    assert Ecto.Date.cast("2015-01-32") == :error
  end

  test "to_string" do
    assert Ecto.Date.to_string(@test_ecto_date) == @test_date
  end
end

defmodule Ecto.TimeTest do
  use ExUnit.Case, async: true

  @test_time "23:50:07"
  @test_ecto_time %Ecto.Time{hour: 23, min: 50, sec: 07}

  test "cast" do
    assert Ecto.Time.cast(@test_time) == {:ok, @test_ecto_time}
    assert Ecto.Time.cast(@test_time <> "Z") == {:ok, @test_ecto_time}
    assert Ecto.Time.cast(@test_time <> ".030") == {:ok, @test_ecto_time}
    assert Ecto.Time.cast(@test_time <> ".030Z") == {:ok, @test_ecto_time}
    assert Ecto.Date.cast("24:01:01") == :error
    assert Ecto.Date.cast("00:61:00") == :error
    assert Ecto.Date.cast("00:00:61") == :error
    assert Ecto.Date.cast("00:00:009") == :error
    assert Ecto.Date.cast("00:00:00.A00") == :error
  end

  test "to_string" do
    assert Ecto.Time.to_string(@test_ecto_time) == @test_time
  end
end

defmodule Ecto.DateTimeTest do
  use ExUnit.Case, async: true

  @test_datetime "2015-01-23T23:50:07"
  @test_ecto_datetime %Ecto.DateTime{year: 2015, month: 1, day: 23, hour: 23, min: 50, sec: 07}

  test "cast" do
    assert Ecto.DateTime.cast("2015-01-23 23:50:07") == {:ok, @test_ecto_datetime}
    assert Ecto.DateTime.cast("2015-01-23T23:50:07") == {:ok, @test_ecto_datetime}
    assert Ecto.DateTime.cast("2015-01-23T23:50:07Z") == {:ok, @test_ecto_datetime}
    assert Ecto.DateTime.cast("2015-01-23T23:50:07.000Z") == {:ok, @test_ecto_datetime}
    assert Ecto.DateTime.cast("2015-01-23P23:50:07") == :error
  end

  test "to_string" do
    assert Ecto.DateTime.to_string(@test_ecto_datetime) == (@test_datetime <> "Z")
  end
end
