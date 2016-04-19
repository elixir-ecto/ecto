defmodule SimpleTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Simple.Repo)
  end

  test "no_prcp_query" do
    result = capture_io(fn ->
      Simple.no_prcp_query
      |> Enum.each(fn(w) -> IO.puts "weather id=#{w.id}, city_id=#{w.city_id}, wdate=#{w.wdate}" end)
    end)

    assert result =~ """
    weather id=5, city_id=1, wdate=2015-09-16
    weather id=8, city_id=2, wdate=2015-09-12
    weather id=11, city_id=3, wdate=2015-09-12
    """
  end

  test "countries_with_weather_query" do
    result = capture_io(fn ->
      Simple.countries_with_weather_query |> Enum.each(fn(c) -> IO.puts c.name end)
    end)

    assert result == """
    United States
    United Kingdom
    """
  end
end
