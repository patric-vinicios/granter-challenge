import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load configuration and
# secrets from environment variables. Do not define any compile-time
# configuration in here, as it won't be applied.
#
# Unlike the stock Phoenix file, this one serves *every* environment:
# a native `mix phx.server` run and the `api` container read the same
# variables, so there is a single place where the deployment surface is
# described. `.env.example` lists all of them with working defaults.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/api start
if System.get_env("PHX_SERVER") do
  config :api, ApiWeb.Endpoint, server: true
end

# CORS origins are read in every environment, including test, so the CORS
# integration test can swap them at runtime.
config :api,
       :cors_origins,
       "CORS_ORIGINS"
       |> System.get_env("http://localhost:5173,http://localhost:3000")
       |> String.split(",", trim: true)
       |> Enum.map(&String.trim/1)

# The test environment is deliberately excluded from everything below:
# `mix test` must run with no exported variable at all, against the
# database defined in config/test.exs (docker-compose.test.yml, port
# 54321), so a stray DATABASE_URL can never point the suite at the
# development database.
if config_env() != :test do
  # Secrets are mandatory outside of test. Booting without one aborts
  # immediately naming the variable, rather than failing later with an
  # obscure signing or token error.
  required_env = fn name, hint ->
    System.get_env(name) ||
      raise """
      environment variable #{name} is missing.
      #{hint}
      """
  end

  secret_key_base =
    required_env.("SECRET_KEY_BASE", "You can generate one by calling: mix phx.gen.secret")

  # Reserved here by F01; consumed by F02's token issuing and verification.
  jwt_secret = required_env.("JWT_SECRET", "You can generate one by calling: mix phx.gen.secret")

  config :api, :jwt_secret, jwt_secret

  bind_ip =
    "BIND_IP"
    |> System.get_env("127.0.0.1")
    |> String.to_charlist()
    |> :inet.parse_address()
    |> case do
      {:ok, address} -> address
      {:error, _reason} -> raise "environment variable BIND_IP is not a valid IP address"
    end

  config :api, ApiWeb.Endpoint,
    http: [ip: bind_ip, port: String.to_integer(System.get_env("PORT", "4000"))],
    secret_key_base: secret_key_base

  # When DATABASE_URL is set it wins over the per-environment credentials,
  # which is what lets the container and a native run share this file.
  if database_url = System.get_env("DATABASE_URL") do
    maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

    config :api, Api.Repo,
      url: database_url,
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
      socket_options: maybe_ipv6
  end
end

if config_env() == :prod do
  host = System.get_env("PHX_HOST") || "example.com"

  config :api, ApiWeb.Endpoint, url: [host: host, port: 443, scheme: "https"]
end
