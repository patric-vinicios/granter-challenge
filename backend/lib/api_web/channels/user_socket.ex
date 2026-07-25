defmodule ApiWeb.UserSocket do
  @moduledoc """
  The transport that turns the token behind every HTTP request into a live
  connection.

  A browser `WebSocket` carries no header a client controls, so the credential
  arrives as the `token` connect param and is resolved through the very same
  `Api.Accounts.Guardian` entry point the HTTP pipeline uses — one credential a
  client manages, and one place the verification rules live. That the token
  travels in a URL is acceptable here for reasons that would not hold in
  general: it is short-lived by policy and the connection is TLS in every
  deployed environment. Anything but a token naming a real user fails the
  handshake, and no channel is reachable without one.

  `id/1` derives `"user_socket:<user_id>"`, so a single
  `Endpoint.broadcast/3` on that id closes every socket a person holds at once —
  the handle the presence and membership-revocation paths reach a user's
  connections through.
  """

  use Phoenix.Socket

  alias Api.Accounts.Guardian
  alias ApiWeb.EventLog

  channel "conversation:*", ApiWeb.ConversationChannel
  channel "user:*", ApiWeb.UserChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Guardian.resource_from_token(token) do
      {:ok, user, _claims} ->
        Logger.metadata(user_id: user.id)
        {:ok, assign(socket, current_user: user, current_user_id: user.id)}

      _error ->
        EventLog.socket_rejected(:invalid_token)
        :error
    end
  end

  def connect(_params, _socket, _connect_info) do
    EventLog.socket_rejected(:no_token)
    :error
  end

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.current_user_id}"
end
