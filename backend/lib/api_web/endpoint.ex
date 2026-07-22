defmodule ApiWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :api

  # Everything the browser stack needs lives behind this flag. A bearer-token
  # JSON API reads no cookie, so in `test` and `prod` no session plug, no
  # `/live` socket and no request logger are compiled at all -- they exist
  # only so the LiveDashboard diagnostic works in development.
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

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :api
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  # JSON is the only representation this service accepts or produces. A body
  # with any other content type falls through unparsed and the router's
  # `:accepts` step answers 415.
  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Phoenix.json_library()

  plug Plug.Head

  # LiveDashboard's `:fetch_session` / `:protect_from_forgery` pipeline needs
  # a session to have been fetched; no API route ever reads it.
  if Application.compile_env(:api, :dev_routes) do
    plug Plug.Session, @session_options
  end

  # Ahead of the router so a preflight is answered before any pipeline -- and,
  # from F02 onwards, before authentication rejects the credential-less
  # OPTIONS request.
  plug CORSPlug,
    origin: &ApiWeb.Endpoint.cors_origins/0,
    methods: ["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    headers: ["authorization", "content-type"]

  plug ApiWeb.Router

  @doc """
  Browser origins allowed to call the API, read on every request so
  `CORS_ORIGINS` takes effect without recompiling.
  """
  def cors_origins do
    Application.get_env(:api, :cors_origins, ["http://localhost:5173"])
  end
end
