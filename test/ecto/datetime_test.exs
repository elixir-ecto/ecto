defmodule Ecto.DateTest do
  use ExUnit.Case, async: true

  @test_date "2015-01-23"
  @test_ecto_date %Ecto.Date{year: 2015, month: 1, day: 23}
  
  test "cast" do
    assert Ecto.Date.cast(@test_date) == {:ok, @test_ecto_date}
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
  end

  test "to_string" do
    assert Ecto.Time.to_string(@test_ecto_time) == @test_time
  end
end

defmodule Ecto.DateTimeTest do
  use ExUnit.Case, async: true

  @test_datetime "2015-01-23T23:50:07Z"
  @test_ecto_datetime %Ecto.DateTime{year: 2015, month: 1, day: 23, hour: 23, min: 50, sec: 07}
  
  test "cast" do
    assert Ecto.DateTime.cast(@test_datetime) == {:ok, @test_ecto_datetime}
  end

  test "to_string" do
    assert Ecto.DateTime.to_string(@test_ecto_datetime) == @test_datetime
  end
end