# Simple

To run this example, you need to ensure postgres is up and running with a `postgres` username and `postgres` password. If you want to run with another credentials, just change the settings in the `config/config.exs` file.

Then, from the command line:

* `mix do deps.get, compile`
* `mix ecto.create`
* `mix ecto.migrate`
* `iex -S mix`

Inside IEx, run:

* `Simple.sample_query`
