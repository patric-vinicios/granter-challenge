defmodule ApiWeb.ErrorController do
  @moduledoc """
  Target of the router's catch-all route.

  Without it an unmatched path raises `Phoenix.Router.NoRouteError`, which
  renders Phoenix's HTML debug page in development -- a surprise for a client
  that only ever parses JSON.
  """

  use ApiWeb, :controller

  # Rendered directly: with no pipeline, no format was negotiated for render/2.
  @spec not_found(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def not_found(conn, _params) do
    conn
    |> put_status(:not_found)
    |> json(ApiWeb.ErrorJSON.render("404.json", %{}))
  end
end
