defmodule ApiWeb.ConversationJSON do
  @moduledoc """
  The private conversation shape: the thread, the caller's own read marker, and
  the other participant embedded through `ApiWeb.UserJSON.data/1`.

  Both fields that depend on who is asking are derived from the caller: the
  counterpart is the participant that is not the caller, and `last_read_at` is
  the caller's own marker, not the counterpart's. Nesting the counterpart rather
  than flattening it reuses the one user shape contacts and, later, group members
  and message senders share, so a field added to the user object reaches this
  endpoint without a change here.

  The group rendering of this endpoint — name, creator, member list — belongs to
  the feature that owns groups; this module renders the `:private` branch.
  """

  alias Api.Conversations.Conversation
  alias ApiWeb.UserJSON

  def show(%{conversation: conversation, caller: caller}),
    do: %{conversation: data(conversation, caller)}

  def data(%Conversation{} = conversation, caller) do
    mine = Enum.find(conversation.participants, &(&1.user_id == caller.id))
    counterpart = Enum.find(conversation.participants, &(&1.user_id != caller.id))

    %{
      id: conversation.id,
      type: conversation.type,
      last_read_at: mine && mine.last_read_at,
      counterpart: UserJSON.data(counterpart.user)
    }
  end
end
