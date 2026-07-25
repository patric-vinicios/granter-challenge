defmodule ApiWeb.ConversationChannel do
  @moduledoc """
  Real-time message traffic for one conversation, on topic `conversation:<id>`.

  ## Join

  `join/3` asks the predicate the REST history endpoint asks,
  `Conversations.participant?/2`, so the live and HTTP surfaces never disagree
  about who belongs. An outsider, a departed member, an unknown id and a
  malformed id all collapse into one `unauthorized` reply.

  ## Sending

  `new_message` persists before it broadcasts. Were the broadcast first, a
  rejected insert would have already painted a message into every window that no
  history read returns. Inserting first makes the worst case a durable but
  momentarily undelivered message, which the client repairs on its next history
  fetch — so history stays the single source of truth and this channel replays
  nothing on join. The sender receives its persisted record once as the reply,
  correlated by `client_ref`, and is excluded from the broadcast; a second
  device of the same user is a plain subscriber, since the exclusion is by
  channel process, not by user.

  ## Presence

  Presence is relayed, never tracked here. On join the channel pushes
  `presence:state` for this conversation's participants and subscribes to each
  participant's personal topic, forwarding every later `presence:diff`. It
  subscribes to no other user topic, so a stranger's change has no path to the
  client — the no-leak guarantee is structural. Those subscriptions also carry
  `conversation:updated`, which belongs to the personal topic and is ignored
  here.
  """

  use ApiWeb, :channel

  alias Api.Conversations
  alias Api.Messages
  alias ApiWeb.ChangesetJSON
  alias ApiWeb.Conversations.ConversationJSON
  alias ApiWeb.Conversations.MessageJSON
  alias ApiWeb.Endpoint
  alias ApiWeb.EventLog
  alias ApiWeb.Presence
  alias ApiWeb.RateLimiter
  alias Phoenix.Socket.Broadcast

  intercept ["membership_revoked"]

  @impl true
  def join("conversation:" <> conversation_id, _payload, socket) do
    if Conversations.participant?(conversation_id, socket.assigns.current_user) do
      send(self(), :after_join)
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
        EventLog.message_rate_limited(user.id, retry_after_ms)
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

  # Snapshot the participants once and both push their current presence and
  # subscribe to their personal topics. Snapshotting at join is enough: a
  # membership change mid-session already forces a rejoin through the revocation
  # path, so live re-subscription is never needed.
  @impl true
  def handle_info(:after_join, socket) do
    participant_ids = Conversations.participant_ids(socket.assigns.conversation_id)

    state =
      Enum.reduce(participant_ids, %{}, fn id, acc ->
        Map.merge(acc, Presence.list("user:#{id}"))
      end)

    push(socket, "presence:state", state)

    for id <- participant_ids, do: Phoenix.PubSub.subscribe(Api.PubSub, "user:#{id}")

    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: "presence_diff", payload: diff}, socket) do
    push(socket, "presence:diff", diff)
    {:noreply, socket}
  end

  # Every other message on the subscribed personal topics — `conversation:updated`
  # in particular — is meant for the user's own channel, not this one.
  def handle_info(_msg, socket), do: {:noreply, socket}

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
