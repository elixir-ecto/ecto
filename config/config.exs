use Mix.Config

# Disable sasl reports enabled by sbroker
config :sasl, :sasl_error_logger, :false

import_config "#{Mix.env}.exs"
