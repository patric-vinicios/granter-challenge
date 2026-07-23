defmodule ApiWeb.UserChannel do
  @moduledoc """
  A user's private notification topic.

  One join rule — the topic id must be the connected user's own — so a socket
  can never subscribe to someone else's notifications and a well-formed id and a
  malformed one are refused with the same answer. It carries no inbound event:
  it exists to receive `conversation:updated` today and the presence traffic a
  later feature will add, and an unexpected push is answered rather than left to
  hang.
  """

  use ApiWeb, :channel

  @impl true
  def join("user:" <> user_id, _payload, socket) do
    if user_id == socket.assigns.current_user_id do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{reason: "unknown_event"}}, socket}
  end
end
