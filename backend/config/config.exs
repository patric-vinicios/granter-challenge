# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

alias Api.Repo

config :api,
  ecto_repos: [Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true],
  env: config_env()

config :api, Repo,
  migration_primary_key: [type: :binary_id],
  migration_foreign_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime_usec]

# Configure the endpoint
config :api, ApiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: ApiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Api.PubSub,
  # Only LiveDashboard needs this; the API signs nothing with it.
  live_view: [signing_salt: "ee2QZZUQ"]

# Token issuance. The signing secret is deliberately absent here: it comes from
# JWT_SECRET at runtime, so no environment ships with a compiled-in default.
config :api, Api.Accounts.Guardian,
  issuer: "api",
  ttl: {7, :days},
  # Guardian would default to HS512; HS256 is the published contract and is
  # what a client library expects from this API.
  allowed_algos: ["HS256"]

# Failed-login ceiling: per IP and per username, over a fixed window.
config :api, ApiWeb.LoginThrottle, ip_limit: 10, user_limit: 5, window_ms: 60_000

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
