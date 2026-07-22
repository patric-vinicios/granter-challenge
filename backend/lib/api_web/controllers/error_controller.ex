defmodule ApiWeb.ErrorController do
  @moduledoc """
  Target of the router's catch-all route.

  Without it an unmatched path raises `Phoenix.Router.NoRouteError`, which in
  development renders Phoenix's HTML debug page -- a surprise for a client
  that only ever parses JSON. Routing the miss to a real action means the same
  envelope comes back in every environment.
  """

  use ApiWeb, :controller

  # The envelope is rendered directly rather than through `render/2`: this
  # route runs through no pipeline, so `:accepts` never negotiated a format
  # and there is nothing for the view layer to resolve a template against.
  def not_found(conn, _params) do
    conn
    |> put_status(:not_found)
    |> json(ApiWeb.ErrorJSON.render("404.json", %{}))
  end
end
