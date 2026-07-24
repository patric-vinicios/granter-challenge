import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :api, Api.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 54_321,
  database: "api_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :api, ApiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "hF9b49Jxfj2BbC3G3/oRZRFyhUtUcUpoVDlWbhAmyhdY0iOKlt8EsMqZ4AMQZwDc",
  server: false

# runtime.exs deliberately skips :test, so the suite needs its own literal
# signing secret rather than an exported variable.
config :api, Api.Accounts.Guardian,
  secret_key: "kx0lHNTBpXcMBmoP4LJ9qWvVSBLpDgLR8Yfr2mS6TnGZOAkcYRSjS5ecvXi7RgLK"

# Argon2 is deliberately slow. At production cost a suite that inserts users
# per test spends most of its wall clock hashing, so test uses the floor.
config :argon2_elixir, t_cost: 1, m_cost: 8

# Raise the login ceiling out of the suite's way; the throttle test lowers it
# for itself against a unique key.
config :api, ApiWeb.LoginThrottle, ip_limit: 100_000, user_limit: 100_000, window_ms: 60_000

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
