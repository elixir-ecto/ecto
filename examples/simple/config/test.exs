use Mix.Config

config :simple, Simple.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "ecto_simple_test",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox
