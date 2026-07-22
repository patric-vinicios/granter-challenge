defmodule ApiWeb.AuthPipeline do
  @moduledoc """
  Guard for every route that needs an identity.

  Verifies the `Authorization: Bearer` header, refuses the request when no
  valid token is present, loads the user the token's subject names, and leaves
  it on `conn.assigns.current_user`. A failure at any step is rendered by
  `ApiWeb.AuthErrorHandler` in the API's standard envelope.
  """

  use Guardian.Plug.Pipeline,
    otp_app: :api,
    module: Api.Accounts.Guardian,
    error_handler: ApiWeb.AuthErrorHandler

  plug Guardian.Plug.VerifyHeader, scheme: "Bearer"
  plug Guardian.Plug.EnsureAuthenticated
  # `allow_blank: false` so a token whose subject was deleted fails here
  # rather than reaching a controller with a nil current_user.
  plug Guardian.Plug.LoadResource, allow_blank: false
  plug ApiWeb.Plugs.AssignCurrentUser
end
