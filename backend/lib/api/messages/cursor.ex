defmodule Api.Messages.Cursor do
  @moduledoc """
  The keyset position of one message in a conversation's history, ordered by
  `(inserted_at, seq)`. `Api.Cursor` owns the encoding; this only names the
  columns that order the list.
  """

  alias Api.Cursor
  alias Api.Messages.Message

  @typedoc "The `(inserted_at, seq)` pair a cursor encodes."
  @type position :: {DateTime.t(), integer()}

  @types [:datetime, :integer]

  @doc """
  Encodes a message's keyset position.

  ## Parameters

    * `message_or_position` — a `%Message{}`, or an `{inserted_at, seq}` pair

  ## Examples

      iex> Api.Messages.Cursor.encode({~U[2026-07-24 12:00:00Z], 42})
      "MjAyNi0wNy0yNFQxMjowMDowMFp8NDI"
  """
  @spec encode(Message.t() | position()) :: String.t()
  def encode(%Message{inserted_at: inserted_at, seq: seq}), do: encode({inserted_at, seq})
  def encode({%DateTime{} = inserted_at, seq}), do: Cursor.encode([inserted_at, seq])

  @doc """
  Decodes a message cursor into its `{inserted_at, seq}` pair.

  ## Parameters

    * `cursor` — an opaque cursor string produced by `encode/1`

  Returns `{:ok, {inserted_at, seq}}` or `{:error, :invalid_cursor}`.

  ## Examples

      iex> Api.Messages.Cursor.decode("garbage")
      {:error, :invalid_cursor}
  """
  @spec decode(term()) :: {:ok, position()} | {:error, :invalid_cursor}
  def decode(cursor) do
    case Cursor.decode(cursor, @types) do
      {:ok, [inserted_at, seq]} -> {:ok, {inserted_at, seq}}
      {:error, :invalid_cursor} -> {:error, :invalid_cursor}
    end
  end
end
