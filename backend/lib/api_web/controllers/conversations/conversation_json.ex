defmodule ApiWeb.Conversations.ConversationJSON do
  @moduledoc """
  The conversation shape, dispatched on `type`.

  A private conversation renders the thread, the caller's own read marker and
  the other participant; a group renders its name, creator, active member count
  and the ordered member list. Both embed each user through
  `ApiWeb.Accounts.UserJSON.data/1`, so the client reuses one user type across contacts,
  private counterparts and group members, and a field added to the user object
  reaches every one of them without a change here.
  """

  alias Api.Conversations.Conversation
  alias Api.Messages.Message
  alias ApiWeb.Accounts.UserJSON
  alias ApiWeb.Presence

  # The `conversation:updated` preview is a plain leading slice, not the
  # whole-word truncation the inbox list applies to its own payload: this event
  # only tells a client which thread moved and roughly what it now says.
  @preview_limit 120

  @spec show(%{conversation: Conversation.t(), caller: Api.Accounts.User.t()}) :: map()
  def show(%{conversation: conversation, caller: caller}),
    do: %{conversation: data(conversation, caller)}

  @doc """
  One page of the inbox: the entries, the cursor that opens the next page and
  whether there is one. `next_cursor` is null exactly when `has_more` is false,
  so a client stops on either without having to compare counts against a page
  size it did not choose.
  """
  @spec index(%{
          conversations: [Api.Conversations.summary()],
          next_cursor: String.t() | nil,
          has_more: boolean()
        }) :: map()
  def index(%{conversations: conversations, next_cursor: next_cursor, has_more: has_more}) do
    %{
      conversations: Enum.map(conversations, &summary/1),
      next_cursor: next_cursor,
      has_more: has_more
    }
  end

  @doc """
  One inbox entry. `counterpart` and `member_count` are mutually exclusive — each
  is null for the type it does not describe — and `last_message` is a nested
  object or null so "never used" is a single check. The body arrives already
  truncated from the context.
  """
  @spec summary(Api.Conversations.summary()) :: map()
  def summary(entry) do
    %{
      id: entry.id,
      type: entry.type,
      title: entry.title,
      counterpart: entry.counterpart && UserJSON.data(entry.counterpart),
      member_count: entry.member_count,
      last_message: last_message(entry.last_message),
      unread_count: entry.unread_count,
      unread_overflow: entry.unread_overflow,
      last_read_at: entry.last_read_at
    }
  end

  @spec read(%{result: %{conversation_id: Ecto.UUID.t(), last_read_at: DateTime.t()}}) :: map()
  def read(%{result: %{conversation_id: id, last_read_at: last_read_at}}),
    do: %{conversation_id: id, last_read_at: last_read_at, unread_count: 0}

  @doc """
  The `conversation:updated` payload for one recipient: which conversation
  moved, a truncated preview of the new message with its sender and timestamp,
  and whether it counts as unread for this recipient.

  `unread` is simply "someone other than you sent it" — the live count belongs
  to the inbox feature, so this event carries the boolean it actually knows and
  couples to none of that feature's `last_read_at` semantics.
  """
  @spec updated(%{message: Message.t(), recipient_id: Ecto.UUID.t()}) :: map()
  def updated(%{message: %Message{} = message, recipient_id: recipient_id}) do
    %{
      conversation_id: message.conversation_id,
      last_message: %{
        preview: preview(message.body),
        sender_id: message.sender_id,
        inserted_at: message.inserted_at
      },
      unread: message.sender_id != recipient_id
    }
  end

  defp last_message(nil), do: nil

  defp last_message(message) do
    %{
      id: message.id,
      body: message.body,
      sender_id: message.sender_id,
      inserted_at: message.inserted_at
    }
  end

  defp preview(body) when is_binary(body) do
    if String.length(body) > @preview_limit,
      do: String.slice(body, 0, @preview_limit),
      else: body
  end

  @spec data(Conversation.t(), Api.Accounts.User.t()) :: map()
  def data(%Conversation{type: :private} = conversation, caller) do
    mine = Enum.find(conversation.participants, &(&1.user_id == caller.id))
    counterpart = Enum.find(conversation.participants, &(&1.user_id != caller.id))

    %{
      id: conversation.id,
      type: conversation.type,
      last_read_at: mine && mine.last_read_at,
      counterpart: with_online(counterpart.user)
    }
  end

  def data(%Conversation{type: :group} = conversation, _caller) do
    members = Enum.map(conversation.participants, &with_online(&1.user))

    %{
      id: conversation.id,
      type: "group",
      name: conversation.name,
      creator_id: conversation.creator_id,
      member_count: length(members),
      members: members
    }
  end

  # `online` lives only in the conversation detail, not the shared user object: a
  # message sender or contact entry has no online status to answer, and scoping
  # it to conversation members keeps presence where a shared conversation lets
  # the caller see it. The value is an O(1) presence lookup, no database.
  defp with_online(user),
    do: Map.put(UserJSON.data(user), :online, Presence.online?(user.id))
end
