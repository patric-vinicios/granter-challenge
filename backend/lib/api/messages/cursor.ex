defmodule Api.Messages.Cursor do
  @moduledoc """
  Encodes and decodes the position of one message in a conversation's history.

  A cursor is the two ordering columns of a row — `inserted_at` and `id` —
  joined and base64url-encoded without padding, so it survives a query string
  without escaping and carries no `=`, `+` or `/`.

  It is opaque but deliberately not signed, and the distinction matters: a
  cursor is not a capability. By the time one is decoded, the read gate has
  already decided that this caller may read this conversation; the cursor only
  chooses where inside it to start, so the worst a forged value can do is skip
  its own author's messages. Signing would buy an access-control property the
  authorization layer already owns, at the price of invalidating every in-flight
  cursor whenever the signing secret rotates.

  Decoding is strict at every step and collapses each failure into one error, so
  no distinction between failure modes is observable and a malformed cursor can
  never be mistaken for an absent one. Falling back to the newest page would
  hand a client a duplicate of content it already holds, with no way to notice.
  """

  alias Api.Messages.Message

  @typedoc "The `(inserted_at, id)` pair a cursor encodes."
  @type position :: {DateTime.t(), Ecto.UUID.t()}

  @separator "|"

  @doc """
  The opaque position of `message` in its conversation.
  """
  @spec encode(Message.t() | position()) :: String.t()
  def encode(%Message{inserted_at: inserted_at, id: id}), do: encode({inserted_at, id})

  def encode({%DateTime{} = inserted_at, id}) do
    [DateTime.to_iso8601(inserted_at), id]
    |> Enum.join(@separator)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Reads a cursor back into the `(inserted_at, id)` pair the keyset query bounds
  on, or `{:error, :invalid_cursor}` if any step of it fails.
  """
  @spec decode(term()) :: {:ok, position()} | {:error, :invalid_cursor}
  def decode(cursor) when is_binary(cursor) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         [timestamp, id] <- String.split(raw, @separator),
         {:ok, inserted_at, 0} <- DateTime.from_iso8601(timestamp),
         {:ok, uuid} <- Ecto.UUID.cast(id) do
      {:ok, {inserted_at, uuid}}
    else
      _ -> {:error, :invalid_cursor}
    end
  end

  def decode(_cursor), do: {:error, :invalid_cursor}
end
