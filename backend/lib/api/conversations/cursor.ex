defmodule Api.Conversations.Cursor do
  @moduledoc """
  Encodes and decodes the position of one conversation in the caller's inbox.

  The inbox is ordered by last activity, then by the conversation's own creation
  time, then by its id, and a cursor carries all three. Carrying fewer would not
  be a smaller cursor but a broken one: the keyset bound is a strict comparison,
  so any component left out is a component the bound cannot break ties on, and
  every row tied on the components that remain is skipped. Two conversations
  whose last messages share a timestamp — one bulk import, one busy second — are
  enough to lose a conversation from the list with no way for the client to
  notice.

  Activity is nullable because a conversation that has never been used has no
  last message. Absent sorts last rather than as a missing value, which is the
  order the inbox promises, so it is encoded as a sentinel and compared as
  `-infinity` rather than as `NULL`.

  `Api.Cursor` owns the encoding and the strictness; what belongs here is only
  which columns order this list.
  """

  alias Api.Cursor

  @typedoc "The `(activity, inserted_at, id)` triple a cursor encodes."
  @type position :: {DateTime.t() | nil, DateTime.t(), Ecto.UUID.t()}

  @types [{:nullable, :datetime}, :datetime, :uuid]

  @doc """
  The opaque position of one inbox entry.
  """
  @spec encode(position()) :: String.t()
  def encode({activity, %DateTime{} = inserted_at, id}),
    do: Cursor.encode([activity, inserted_at, id])

  @doc """
  Reads a cursor back into the triple the keyset query bounds on, or
  `{:error, :invalid_cursor}` if any step of it fails.
  """
  @spec decode(term()) :: {:ok, position()} | {:error, :invalid_cursor}
  def decode(cursor) do
    case Cursor.decode(cursor, @types) do
      {:ok, [activity, inserted_at, id]} -> {:ok, {activity, inserted_at, id}}
      {:error, :invalid_cursor} -> {:error, :invalid_cursor}
    end
  end
end
