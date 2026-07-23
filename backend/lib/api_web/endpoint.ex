defmodule ApiWeb.Endpoint do
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
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
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
  Browser origins allowed to call the API, read per request so `CORS_ORIGINS`
  takes effect without recompiling.
  """
  def cors_origins do
    Application.get_env(:api, :cors_origins, ["http://localhost:5173"])
  end
end
