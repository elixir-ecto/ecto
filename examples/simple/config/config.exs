use Mix.Config

config :simple,
  ecto_repos: [Simple.Repo]

import_config "#{Mix.env}.exs"
