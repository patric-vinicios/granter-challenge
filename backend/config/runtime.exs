import Config

# Serves every environment, not just prod: a native run and the api container
# read the same variables. `.env.example` lists them with working defaults.

# Development reads `.env` when it exists; an exported variable still wins.
if config_env() == :dev do
  dotenv = Path.expand("../.env", __DIR__)

  if File.exists?(dotenv) do
    dotenv
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.each(fn line ->
      case String.split(line, "=", parts: 2) do
        [name, value] ->
          name = String.trim(name)

          if is_nil(System.get_env(name)) do
            System.put_env(name, value |> String.trim() |> String.trim(~s(")) |> String.trim("'"))
          end

        _ ->
          :ok
      end
    end)
  end
end

# Abort naming the variable, rather than failing later on an obscure error.
required_env = fn name, hint ->
  System.get_env(name) ||
    raise """
    environment variable #{name} is missing.
    #{hint}
    """
end

if System.get_env("PHX_SERVER") do
  config :api, ApiWeb.Endpoint, server: true
end

cors_origins =
  if config_env() == :prod do
    required_env.(
      "CORS_ORIGINS",
      "Comma-separated browser origins allowed to call this API, scheme included."
    )
  else
    System.get_env("CORS_ORIGINS", "http://localhost:5173,http://localhost:3000")
  end

config :api,
       :cors_origins,
       cors_origins
       |> String.split(",", trim: true)
       |> Enum.map(&String.trim/1)

config :api, :trust_proxy_headers, System.get_env("TRUST_PROXY_HEADERS") in ~w(true 1)

# Test is excluded below so `mix test` needs no exported variable, and a stray
# DATABASE_URL can never point the suite at the development database.
if config_env() != :test do
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
  database_url =
    if config_env() == :prod do
      required_env.("DATABASE_URL", "Expected an ecto://user:password@host/database URL.")
    else
      System.get_env("DATABASE_URL")
    end

  if database_url do
    maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

    ssl_opts =
      if System.get_env("DATABASE_SSL") in ~w(true 1) do
        [
          ssl: [
            verify: :verify_peer,
            cacerts: :public_key.cacerts_get(),
            server_name_indication: to_charlist(URI.parse(database_url).host),
            customize_hostname_check: [
              match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
            ]
          ]
        ]
      else
        []
      end

    config :api,
           Api.Repo,
           [
             url: database_url,
             pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
             socket_options: maybe_ipv6
           ] ++ ssl_opts
  end
end

if config_env() == :prod do
  host =
    required_env.("PHX_HOST", "The public hostname this API answers on, without a scheme.")

  config :api, ApiWeb.Endpoint, url: [host: host, port: 443, scheme: "https"]
end
