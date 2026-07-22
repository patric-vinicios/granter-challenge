defmodule ApiWeb.MessageJSON do
  @moduledoc """
  The one message shape the API returns.

  `data/1` stays public and independent of the page around it, because the
  real-time broadcast and the search result render the very same object: a
  client writes one message type, and a field added here reaches all three
  without a change at either call site.

  The sender is embedded through `ApiWeb.UserJSON.data/1` rather than copied
  into the message row. A renamed user therefore renders correctly in history
  written years earlier, and presence reaches message senders with no change
  here at all.
  """

  alias Api.Messages.Message
  alias ApiWeb.UserJSON

  @doc """
  One page of history: the messages ascending by `(inserted_at, id)`, the cursor
  that fetches the page before it, and whether one exists.
  """
  def index(%{messages: messages, next_cursor: next_cursor, has_more: has_more}) do
    %{
      messages: Enum.map(messages, &data/1),
      next_cursor: next_cursor,
      has_more: has_more
    }
  end

  @doc """
  The canonical message object. `body` is rendered verbatim: escaping it is the
  client's obligation, and the bytes returned are the bytes that were sent.
  """
  def data(%Message{} = message) do
    %{
      id: message.id,
      conversation_id: message.conversation_id,
      body: message.body,
      inserted_at: message.inserted_at,
      sender: UserJSON.data(message.sender)
    }
  end
end
