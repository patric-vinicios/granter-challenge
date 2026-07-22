defmodule ApiWeb.ConversationJSON do
  @moduledoc """
  The conversation shape, dispatched on `type`.

  A group renders its name, creator, active member count and the ordered member
  list, each member embedded through `ApiWeb.UserJSON.data/1` so the client
  reuses one user type across contacts, message senders and group members. The
  private-conversation feature adds its own `data/1` clause beside this one, so
  both kinds render through a single view.
  """

  alias Api.Conversations.Conversation
  alias ApiWeb.UserJSON

  def show(%{conversation: conversation}), do: %{conversation: data(conversation)}

  def create(%{conversation: conversation}), do: %{conversation: data(conversation)}

  def data(%Conversation{type: :group} = conversation) do
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
