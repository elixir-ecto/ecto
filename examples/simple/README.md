# Simple

To run this example, you need to ensure postgres is up and running with a `postgres` username and `postgres` password. If you want to run with other credentials, just change the settings in the `config/config.exs` file.

Then, from the command line:

* `mix do deps.get, compile`
* `mix ecto.create`
* `mix ecto.migrate`
* `mix run priv/repo/seeds.exs`
* `iex -S mix`

Inside IEx, run:

* `Simple.no_prcp_query` for a list of all weather rows in the weather table with no prcp.
* `Simple.countries_with_weather_query` for all countries and their weather.

Print results inside IEx:

```elixir
iex(1)> Simple.no_prcp_query |> Enum.each (fn(w) -> IO.puts "weather id=#{w.id}, city_id=#{w.city_id}, wdate=#{w.wdate}" end)
weather id=5, city_id=1, wdate=2015-09-16
weather id=8, city_id=2, wdate=2015-09-12
weather id=11, city_id=3, wdate=2015-09-12
:ok

iex(2)> Simple.countries_with_weather_query |> Enum.each (fn(c) -> IO.puts c.name end)
United States
United Kingdom
:ok
```
