defmodule ApiWeb.Endpoint do
  @moduledoc """
  The Phoenix endpoint — the plug pipeline every request and socket passes
  through before the router.

  It mounts `ApiWeb.UserSocket` for the real-time layer, parses JSON bodies, and
  applies CORS from the `CORS_ORIGINS` allowlist (shared with the socket's
  origin check). The LiveDashboard browser stack is compiled only when
  `:dev_routes` is set.
  """

  use Phoenix.Endpoint, otp_app: :api

  # Browser stack exists only for LiveDashboard; test and prod compile none of it.
  if Application.compile_env(:api, :dev_routes) do
    @session_options [
      store: :cookie,
      key: "_api_key",
      signing_salt: "xxCP1aJB",
      same_site: "Lax"
    ]

    socket "/live", Phoenix.LiveView.Socket,
      websocket: [connect_info: [session: @session_options]],
      longpoll: [connect_info: [session: @session_options]]

    plug Phoenix.LiveDashboard.RequestLogger,
      param_key: "request_logger",
      cookie_key: "request_logger"
  end

  # The real-time surface. The token authenticating every HTTP request travels
  # as the `token` connect param; the frame cap keeps a 4000-character body's
  # ~16 KB well clear of the ceiling while refusing anything that could not be a
  # valid message, and the origin allowlist is the one `CORS_ORIGINS` already
  # governs, so both surfaces read a single setting.
  socket "/socket", ApiWeb.UserSocket,
    websocket: [max_frame_size: 65_536, check_origin: {ApiWeb.Endpoint, :cors_origins, []}],
    longpoll: false

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :api
  end

  plug Plug.RequestId

  plug ApiWeb.Plugs.TrustProxyHeaders

  plug Plug.Telemetry,
    event_prefix: [:phoenix, :endpoint],
    log: {__MODULE__, :log_level, []}

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    length: 100_000,
    json_decoder: Phoenix.json_library()

  plug Plug.Head

  if Application.compile_env(:api, :dev_routes) do
    plug Plug.Session, @session_options
  end

  # Before the router, so a preflight is answered ahead of any pipeline that
  # would reject the credential-less OPTIONS request.
  plug CORSPlug,
    origin: &ApiWeb.Endpoint.cors_origins/0,
    methods: ["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    headers: ["authorization", "content-type"]

  plug ApiWeb.Router

  @doc """
  Request log level, consulted per request by `Plug.Telemetry`.

  The health probe is demoted to `:debug` rather than silenced: an orchestrator
  and a load balancer hit it every few seconds, which at `:info` would bury the
  requests an incident is actually about, while `mix phx.server` still shows it.
  """
  @spec log_level(Plug.Conn.t()) :: Logger.level()
  def log_level(%Plug.Conn{path_info: ["api", "health"]}), do: :debug
  def log_level(%Plug.Conn{}), do: :info

  @doc """
  Browser origins allowed to call the API, read per request so `CORS_ORIGINS`
  takes effect without recompiling.
  """
  @spec cors_origins() :: [String.t()]
  def cors_origins do
    Application.get_env(:api, :cors_origins, ["http://localhost:5173"])
  end

  @doc """
  Returns whether the WebSocket origin is allowed.

  Phoenix passes the parsed origin URI to `check_origin` MFA callbacks, while
  CORSPlug uses `cors_origins/0` for HTTP requests. Keep both surfaces backed by
  the same allowlist.
  """
  @spec cors_origins(URI.t()) :: boolean()
  def cors_origins(%URI{} = uri) do
    uri
    |> URI.to_string()
    |> then(&(&1 in cors_origins()))
  end
end
