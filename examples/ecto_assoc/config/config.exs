use Mix.Config

config :ecto_assoc, EctoAssoc.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "ecto_assoc_repo",
  hostname: "localhost"

config :ecto_assoc,
  ecto_repos: [EctoAssoc.Repo]
