defmodule ApiWeb.Router do
  @moduledoc """
  HTTP routes for the JSON API.

  Two pipelines: `:api` for the public health, register and login routes, and
  `:authenticated`, which runs `ApiWeb.AuthPipeline` so every route behind it can
  read `conn.assigns.current_user`. A catch-all at the end renders a JSON 404 for
  any unmatched path, in place of Phoenix's HTML debug page.
  """

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

    scope "/", Accounts do
      post "/auth/register", AuthController, :register
      post "/auth/login", AuthController, :login
    end
  end

  scope "/api", ApiWeb do
    pipe_through :authenticated

    scope "/", Accounts do
      get "/auth/me", AuthController, :me
      delete "/auth/session", AuthController, :logout
    end

    scope "/", Contacts do
      post "/contacts", ContactController, :create
      get "/contacts", ContactController, :index
      delete "/contacts/:id", ContactController, :delete
    end

    scope "/", Conversations do
      get "/conversations", ConversationController, :index
      post "/conversations/private", ConversationController, :create_private
      post "/conversations/groups", ConversationController, :create_group
      get "/conversations/:id", ConversationController, :show
      post "/conversations/:id/read", ConversationController, :mark_read
      post "/conversations/:id/members", ConversationController, :add_members
      # The static `me` segment must be declared before the parameterised one, so
      # Phoenix's top-down match sends "I leave" here rather than into the id cast.
      delete "/conversations/:id/members/me", ConversationController, :leave
      delete "/conversations/:id/members/:user_id", ConversationController, :remove_member

      get "/conversations/:id/messages", MessageController, :index
      # A distinct segment count from `/messages`, so top-down matching has no
      # ordering hazard between the two.
      get "/conversations/:id/messages/search", MessageController, :search
    end
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
