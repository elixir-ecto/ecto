use Mix.Config

config :simple, Simple.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "ecto_simple_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"
