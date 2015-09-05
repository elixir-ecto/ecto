# Simple

To run this example, you need to ensure postgres is up and running with a `postgres` username and `postgres` password. If you want to run with other credentials, just change the settings in the `config/config.exs` file.

Then, from the command line:

* `mix do deps.get, compile`
* `mix ecto.create`
* `mix ecto.migrate`
* `iex -S mix`

Inside IEx, run:

* `Simple.no_prcp_query` for a list of all weather rows in the weather table with no prcp.
* `Simple.countries_with_weather_query` for all countries and their weather.
