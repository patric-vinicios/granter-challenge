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
