defmodule ApiWeb do
  @moduledoc """
  Entrypoint that supplies the shared `use` blocks for the web layer.

  This is a JSON API, so the only `use ApiWeb, ...` targets are `:controller`,
  `:channel`, `:router` and `:verified_routes` — there is no HTML, component or
  LiveView layer. Each block below is injected verbatim into every module that
  opts into it, so it holds imports, `use`s and aliases only; behaviour lives in
  dedicated modules that those modules import.

      use ApiWeb, :controller
      use ApiWeb, :channel

  Root of the `ApiWeb` boundary, which may depend on `Api` and never the
  reverse.
  """

  use Boundary,
    deps: [Api],
    exports: [Endpoint, EventLog, LoginThrottle, Presence, RateLimiter, Telemetry]

  @doc "Expansion for `use ApiWeb, :router` — `Phoenix.Router` plus pipeline imports."
  @spec router() :: Macro.t()
  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  @doc "Expansion for `use ApiWeb, :channel` — `Phoenix.Channel`."
  @spec channel() :: Macro.t()
  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  @doc "Expansion for `use ApiWeb, :controller` — a JSON controller with verified routes."
  @spec controller() :: Macro.t()
  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  @doc "Expansion for `use ApiWeb, :verified_routes` — `~p` route verification."
  @spec verified_routes() :: Macro.t()
  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: ApiWeb.Endpoint,
        router: ApiWeb.Router
    end
  end

  @doc """
  Dispatches `use ApiWeb, which` to the block named by `which`
  (`:controller`, `:channel`, `:router` or `:verified_routes`).
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
