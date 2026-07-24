defmodule ApiWeb.Conversations.MessageJSON do
  @moduledoc """
  The one message shape the API returns.

  `data/1` stays public and independent of the page around it, because the
  real-time broadcast and the search result render the very same object: a
  client writes one message type, and a field added here reaches all three
  without a change at either call site.

  The sender is embedded through `ApiWeb.Accounts.UserJSON.data/1` rather than copied
  into the message row. A renamed user therefore renders correctly in history
  written years earlier, and presence reaches message senders with no change
  here at all.
  """

  alias Api.Messages.Message
  alias ApiWeb.Accounts.UserJSON

  @doc """
  One page of history: the messages ascending by `(inserted_at, id)`, the cursor
  that fetches the page before it, and whether one exists.
  """
  @spec index(Api.Messages.page()) :: map()
  def index(%{messages: messages, next_cursor: next_cursor, has_more: has_more}) do
    %{
      messages: Enum.map(messages, &data/1),
      next_cursor: next_cursor,
      has_more: has_more
    }
  end

  @doc """
  A page of search hits: the matching messages newest-first, each carrying its
  1-based `position` and the `match_offsets` of the term, plus the total-match
  count and whether more than the cap existed.

  Each hit is the canonical message object augmented in place, so a client reads
  a search result with the same message type it reads everywhere else.
  """
  @spec search(Api.Messages.search_page()) :: map()
  def search(%{messages: messages, total_matches: total_matches, truncated: truncated}) do
    %{
      messages: Enum.map(messages, &hit/1),
      total_matches: total_matches,
      truncated: truncated
    }
  end

  defp hit(%{message: message, position: position, match_offsets: match_offsets}) do
    message
    |> data()
    |> Map.merge(%{position: position, match_offsets: match_offsets})
  end

  @doc """
  The canonical message object. `body` is rendered verbatim: escaping it is the
  client's obligation, and the bytes returned are the bytes that were sent.
  """
  @spec data(Message.t()) :: map()
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
