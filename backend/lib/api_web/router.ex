defmodule ApiWeb.Router do
  use ApiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", ApiWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:api, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: ApiWeb.Telemetry
    end
  end

  # Must stay last: it matches everything the routes above did not. It runs
  # through no pipeline on purpose, so a miss answers with the JSON envelope
  # even when the client sent an Accept header this API does not negotiate.
  scope "/", ApiWeb do
    match :*, "/*path", ErrorController, :not_found
  end
end
