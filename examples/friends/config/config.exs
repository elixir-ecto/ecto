import Config

config :friends, Friends.Repo,
  database: "friends_repo",
  hostname: "localhost"

config :friends, ecto_repos: [Friends.Repo]
