defmodule ApiWeb.AuthErrorHandler do
  @moduledoc """
  Translates a token rejection into the API's error envelope.

  It maps Guardian's failure tuples onto the same domain reasons a context
  would return and hands them to `ApiWeb.FallbackController`, so a 401 raised
  by the plug pipeline is byte-identical to a 401 raised inside an action and
  the client parses one shape.
  """

  @behaviour Guardian.Plug.ErrorHandler

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {type, reason}, _opts) do
    ApiWeb.FallbackController.call(conn, {:error, reason_for(type, reason)})
  end

  # Guardian reports expiry through either element depending on which plug
  # rejected the token, and the distinction is worth keeping: only an expired
  # token means "log in again" rather than "this request was malformed".
  defp reason_for(:invalid_token, :token_expired), do: :token_expired
  defp reason_for(:invalid_token, "token_expired"), do: :token_expired
  defp reason_for(:token_expired, _reason), do: :token_expired
  defp reason_for(_type, _reason), do: :unauthenticated
end
