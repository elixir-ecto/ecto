defmodule SimpleDynamo.Dynamo do
  use Dynamo

  config :dynamo,
    # The environment this Dynamo runs on
    env: Mix.env,

    # The OTP application associated with this Dynamo
    otp_app: :simple_dynamo,

    # The endpoint to dispatch requests to
    endpoint: ApplicationRouter,

    # The route from which static assets are served
    # You can turn off static assets by setting it to false
    static_route: "/static"

  # Uncomment the lines below to enable the cookie session store
  # config :dynamo,
  #   session_store: Session.CookieStore,
  #   session_options:
  #     [ key: "_simple_dynamo_session",
  #       secret: "tJ4jAhtsr7Pk4FAbU3EEpRlQKRIdOuVfYK6hOf+WqV+1dcP3j4OsTxR4pPvMcJHu"]

  # Default functionality available in templates
  templates do
    use Dynamo.Helpers
  end
end
