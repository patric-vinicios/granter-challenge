defmodule ApiWeb.ConversationChannel do
  @moduledoc """
  Message traffic for one conversation.

  `join/3` asks the very predicate the REST history endpoint asks —
  `Conversations.participant?/2` — so the live surface can never disagree with
  the HTTP one about who belongs, and an outsider, a departed member, an unknown
  id and a malformed id collapse into one indistinguishable `unauthorized`: a
  socket is not an oracle for ids the REST layer already refuses to confirm.

  `new_message` persists before it broadcasts, and the ordering is about
  failure, not speed. Were the broadcast first, a rejected insert would have
  already painted a message into every participant's window that no history read
  will ever return, with nothing to undo it. Inserting first makes the worst
  case a message that is durable but momentarily undelivered, which the client
  repairs on its next history fetch — history stays the single source of truth,
  which is also why this channel replays nothing on join.

  The sender is answered by the reply and excluded from the broadcast, so it
  gets its persisted record once, correlated by `client_ref`, on the call it is
  already awaiting; a second device of the same user is a plain subscriber and
  receives `message:new` like anyone else, because the exclusion is by the
  sending channel process, not by user.
  """

  use ApiWeb, :channel

  alias Api.Conversations
  alias Api.Messages
  alias ApiWeb.ChangesetJSON
  alias ApiWeb.ConversationJSON
  alias ApiWeb.Endpoint
  alias ApiWeb.MessageJSON
  alias ApiWeb.RateLimiter

  intercept ["membership_revoked"]

  @impl true
  def join("conversation:" <> conversation_id, _payload, socket) do
    if Conversations.participant?(conversation_id, socket.assigns.current_user) do
      {:ok, assign(socket, :conversation_id, conversation_id)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("new_message", payload, socket) do
    user = socket.assigns.current_user
    client_ref = Map.get(payload, "client_ref")

    case RateLimiter.hit(user.id) do
      :ok ->
        persist_and_broadcast(socket, payload, client_ref)

      {:error, retry_after_ms} ->
        reply_error(socket, %{reason: "rate_limited", retry_after_ms: retry_after_ms}, client_ref)
    end
  end

  def handle_in(_event, payload, socket) do
    reply_error(socket, %{reason: "unknown_event"}, Map.get(payload, "client_ref"))
  end

  @impl true
  def handle_out("membership_revoked", %{user_id: user_id}, socket) do
    if user_id == socket.assigns.current_user_id do
      push(socket, "conversation:membership_revoked", %{
        conversation_id: socket.assigns.conversation_id
      })

      {:stop, :normal, socket}
    else
      {:noreply, socket}
    end
  end

  # The insert commits before anything leaves the node, so every event a client
  # receives names a row a history read can return. The fan-out runs after the
  # broadcast and before the reply, adding one query and N local sends to the
  # sender's latency so "every participant is notified" is testable without a
  # sync point.
  defp persist_and_broadcast(socket, payload, client_ref) do
    %{current_user: user, conversation_id: conversation_id} = socket.assigns

    case Messages.create_message(user, conversation_id, %{body: Map.get(payload, "body")}) do
      {:ok, message} ->
        data = MessageJSON.data(message)
        broadcast_from!(socket, "message:new", data)
        notify_participants(conversation_id, message)
        {:reply, {:ok, %{message: data, client_ref: client_ref}}, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        reply_error(
          socket,
          %{reason: "validation_error", fields: ChangesetJSON.fields(changeset)},
          client_ref
        )

      {:error, :not_found} ->
        reply_error(socket, %{reason: "unauthorized"}, client_ref)
    end
  end

  defp notify_participants(conversation_id, message) do
    for recipient_id <- Conversations.participant_ids(conversation_id) do
      Endpoint.broadcast(
        "user:#{recipient_id}",
        "conversation:updated",
        ConversationJSON.updated(%{message: message, recipient_id: recipient_id})
      )
    end
  end

  # `client_ref` is echoed on failures too, so a client can mark the right
  # optimistic bubble as failed rather than guessing which send it was.
  defp reply_error(socket, reason, client_ref) do
    {:reply, {:error, Map.put(reason, :client_ref, client_ref)}, socket}
  end
end
