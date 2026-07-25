defmodule ApiWeb.HealthController do
  @moduledoc """
  Liveness and readiness probe.

  Sits outside every authenticated pipeline: an orchestrator has no
  credentials, and the endpoint has to keep answering precisely when the
  database -- and therefore authentication -- is unavailable.
  """

  use ApiWeb, :controller

  alias Api.Health

  @doc "`GET /api/health` — 200 when the database answers, 503 when it does not."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
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
