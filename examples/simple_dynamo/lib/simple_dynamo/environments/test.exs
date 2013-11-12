config :dynamo,
  # For testing we compile modules on demand,
  # but there isn't a need to reload them.
  compile_on_demand: true,
  reload_modules: false

config :server, port: 8888
