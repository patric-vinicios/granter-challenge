defmodule ApiWeb.HealthController do
  @moduledoc """
  Liveness and readiness probe.

  Deliberately outside every authenticated pipeline: an orchestrator has no
  credentials, and the endpoint has to keep answering precisely when the
  database -- and therefore authentication -- is unavailable.
  """

  use ApiWeb, :controller

  alias Api.Health

  def show(conn, _params) do
    case Health.check() do
      :ok ->
        render(conn, :ok)

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> render(:error)
    end
  end
end
