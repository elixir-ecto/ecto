config :dynamo,
  # In production, modules are compiled up-front.
  compile_on_demand: false,
  reload_modules: false

config :server,
  port: 8888,
  acceptors: 100,
  max_connections: 10000

# config :ssl,
#  port: 8889,
#  keyfile: "/var/www/key.pem",
#  certfile: "/var/www/cert.pem"
