import Config

# Serves every environment, not just prod: a native run and the api container
# read the same variables. `.env.example` lists them with working defaults.

if System.get_env("PHX_SERVER") do
  config :api, ApiWeb.Endpoint, server: true
end

config :api,
       :cors_origins,
       "CORS_ORIGINS"
       |> System.get_env("http://localhost:5173,http://localhost:3000")
       |> String.split(",", trim: true)
       |> Enum.map(&String.trim/1)

# Test is excluded below so `mix test` needs no exported variable, and a stray
# DATABASE_URL can never point the suite at the development database.
if config_env() != :test do
  # Abort naming the variable, rather than failing later on an obscure error.
  required_env = fn name, hint ->
    System.get_env(name) ||
      raise """
      environment variable #{name} is missing.
      #{hint}
      """
  end

  secret_key_base =
    required_env.("SECRET_KEY_BASE", "You can generate one by calling: mix phx.gen.secret")

  jwt_secret = required_env.("JWT_SECRET", "You can generate one by calling: mix phx.gen.secret")

  config :api, Api.Accounts.Guardian, secret_key: jwt_secret

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

  # Set by the container; a native run falls back to config/dev.exs.
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
