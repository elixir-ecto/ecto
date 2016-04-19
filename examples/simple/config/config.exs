use Mix.Config

config :simple,
  ecto_repos: [Simple.Repo]

config :simple, Simple.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "ecto_simple",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"
