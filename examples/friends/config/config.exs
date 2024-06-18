import Config

config :friends, Friends.Repo,
  database: "friends_repo",
  hostname: "localhost",
  username: "postgres",
  password: "postgres",
  port: 5432

config :friends, ecto_repos: [Friends.Repo]
