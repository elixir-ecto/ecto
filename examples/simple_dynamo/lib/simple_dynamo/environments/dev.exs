config :dynamo,
  # Compile modules as they are accessed.
  # This makes development easy as we don't
  # need to explicitly compile files.
  compile_on_demand: true,

  # Every time a module in web/ changes, we
  # will clean up defined modules and pick
  # up the latest versions.
  reload_modules: true,

  # Do not cache static assets, so they
  # are reloaded for every page in development
  cache_static: false,

  # Show a nice debugging exception page
  # in development
  exceptions_handler: Exceptions.Debug

# Run on port 4000 for development
config :server, port: 4000
