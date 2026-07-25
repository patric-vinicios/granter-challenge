defmodule Api.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  # Its own boundary because the composition root is the one place allowed to
  # see both layers; every other module under Api. is barred from ApiWeb.
  use Boundary, top_level?: true, deps: [Api, ApiWeb]

  @impl true
  def start(_type, _args) do
    children = [
      ApiWeb.Telemetry,
      Api.Repo,
      {Phoenix.PubSub, name: Api.PubSub},
      # After its PubSub and ahead of the endpoint, so the tracker exists before
      # the first socket can connect and be tracked.
      ApiWeb.Presence,
      # Ahead of the endpoint so the counter tables and the revocation set exist
      # before the first request or socket can reach them.
      ApiWeb.RateLimiter,
      ApiWeb.LoginThrottle,
      Api.TokenRevocation,
      # Start to serve requests, typically the last entry
      ApiWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Api.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      ApiWeb.EventLog.boot(Application.get_env(:api, :env), ApiWeb.Endpoint.cors_origins())
      {:ok, pid}
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ApiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
