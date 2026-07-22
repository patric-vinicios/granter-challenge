defmodule ApiWeb.Router do
  use ApiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Everything from the contacts feature onward runs through here, so the
  # actions behind it can read conn.assigns.current_user unconditionally.
  pipeline :authenticated do
    plug :accepts, ["json"]
    plug ApiWeb.AuthPipeline
  end

  scope "/api", ApiWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  if Application.compile_env(:api, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: ApiWeb.Telemetry
    end
  end

  # Must stay last, and runs through no pipeline so a miss still answers JSON
  # when the client sent an Accept header this API does not negotiate.
  scope "/", ApiWeb do
    match :*, "/*path", ErrorController, :not_found
  end
end
