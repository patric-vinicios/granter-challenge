defmodule ApiWeb.ConversationJSON do
  @moduledoc """
  The conversation shape, dispatched on `type`.

  A private conversation renders the thread, the caller's own read marker and
  the other participant; a group renders its name, creator, active member count
  and the ordered member list. Both embed each user through
  `ApiWeb.UserJSON.data/1`, so the client reuses one user type across contacts,
  private counterparts and group members, and a field added to the user object
  reaches every one of them without a change here.
  """

  alias Api.Conversations.Conversation
  alias ApiWeb.UserJSON

  def show(%{conversation: conversation, caller: caller}),
    do: %{conversation: data(conversation, caller)}

  def index(%{conversations: conversations}),
    do: %{conversations: Enum.map(conversations, &summary/1)}

  @doc """
  One inbox entry. `counterpart` and `member_count` are mutually exclusive — each
  is null for the type it does not describe — and `last_message` is a nested
  object or null so "never used" is a single check. The body arrives already
  truncated from the context.
  """
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

  def read(%{result: %{conversation_id: id, last_read_at: last_read_at}}),
    do: %{conversation_id: id, last_read_at: last_read_at, unread_count: 0}

  defp last_message(nil), do: nil

  defp last_message(message) do
    %{
      id: message.id,
      body: message.body,
      sender_id: message.sender_id,
      inserted_at: message.inserted_at
    }
  end

  def data(%Conversation{type: :private} = conversation, caller) do
    mine = Enum.find(conversation.participants, &(&1.user_id == caller.id))
    counterpart = Enum.find(conversation.participants, &(&1.user_id != caller.id))

    %{
      id: conversation.id,
      type: conversation.type,
      last_read_at: mine && mine.last_read_at,
      counterpart: UserJSON.data(counterpart.user)
    }
  end

  def data(%Conversation{type: :group} = conversation, _caller) do
    members = Enum.map(conversation.participants, &UserJSON.data(&1.user))

    %{
      id: conversation.id,
      type: "group",
      name: conversation.name,
      creator_id: conversation.creator_id,
      member_count: length(members),
      members: members
    }
  end
end
