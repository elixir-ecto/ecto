use Mix.Config

config :ecto_assoc, EctoAssoc.Repo,
  database: "ecto_assoc_repo",
  hostname: "localhost"

config :ecto_assoc,
  ecto_repos: [EctoAssoc.Repo]
