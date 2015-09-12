# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Simple.Repo.insert!(%SomeModel{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

data = [ 
  {"United States",[
    {"San Francisco", [
        {"2015-09-12", 59, 73, 0.05},
        {"2015-09-13", 60, 71, 0.02},
        {"2015-09-14", 58, 71, 0.03},
        {"2015-09-15", 57, 68, 0.01},
        {"2015-09-16", 55, 70, 0.00},
        {"2015-09-17", 58, 73, 0.08},
        {"2015-09-18", 60, 72, 0.07}
    ]},
    {"New York", [
        {"2015-09-12", 70, 79, 0.00},
        {"2015-09-13", 59, 76, 0.02},
        {"2015-09-14", 62, 78, 0.01}
    ]}
  ]},
  {"United Kingdom",[
    {"London", [
        {"2015-09-12", 63, 74, 0.00},
        {"2015-09-13", 56, 75, 0.01},
        {"2015-09-14", 58, 73, 0.02}
    ]}
  ]}
]

defmodule Seeds do
  # Start import
  def import_data(data) do
    import_countries data 
  end

  # Import countries
  defp import_countries([]), do: nil
  defp import_countries([{country_name, cities}=h|t]) do
    country = Simple.Repo.insert!(%Country{name: country_name})
    import_cities country, cities
    import_countries t
  end

  # Import cities
  defp import_cities(_,[]), do: nil
  defp import_cities(country, [{city_name,weather}=h|t]) do
    city = Simple.Repo.insert!(%City{name: city_name, country_id: country.id})
    import_weather city, weather
    import_cities country, t
  end

  # Import weather
  defp import_weather(_,[]), do: nil
  defp import_weather(city, [{wdate,temp_lo,temp_hi,prcp}=h|t]) do
    {:ok, ecto_date} = Ecto.Date.cast(wdate)
    Simple.Repo.insert!(%Weather{wdate: ecto_date, temp_lo: temp_lo, temp_hi: temp_hi, prcp: prcp, city_id: city.id})
    import_weather city, t
  end
end

Seeds.import_data(data)

