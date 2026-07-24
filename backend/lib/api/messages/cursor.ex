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

  @spec encode(Message.t() | position()) :: String.t()
  def encode(%Message{inserted_at: inserted_at, seq: seq}), do: encode({inserted_at, seq})
  def encode({%DateTime{} = inserted_at, seq}), do: Cursor.encode([inserted_at, seq])

  @spec decode(term()) :: {:ok, position()} | {:error, :invalid_cursor}
  def decode(cursor) do
    case Cursor.decode(cursor, @types) do
      {:ok, [inserted_at, seq]} -> {:ok, {inserted_at, seq}}
      {:error, :invalid_cursor} -> {:error, :invalid_cursor}
    end
  end
end
