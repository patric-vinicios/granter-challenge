defmodule Api.Messages.Cursor do
  @moduledoc """
  Encodes and decodes the position of one message in a conversation's history.

  History is ordered by `(inserted_at, id)`, so those are the two components the
  cursor carries and the two the keyset query bounds on. `Api.Cursor` owns the
  encoding and the strictness; what belongs here is only which columns order
  this list.
  """

  alias Api.Cursor
  alias Api.Messages.Message

  @typedoc "The `(inserted_at, id)` pair a cursor encodes."
  @type position :: {DateTime.t(), Ecto.UUID.t()}

  @types [:datetime, :uuid]

  @doc """
  The opaque position of `message` in its conversation.
  """
  @spec encode(Message.t() | position()) :: String.t()
  def encode(%Message{inserted_at: inserted_at, id: id}), do: encode({inserted_at, id})

  def encode({%DateTime{} = inserted_at, id}), do: Cursor.encode([inserted_at, id])

  @doc """
  Reads a cursor back into the `(inserted_at, id)` pair the keyset query bounds
  on, or `{:error, :invalid_cursor}` if any step of it fails.
  """
  @spec decode(term()) :: {:ok, position()} | {:error, :invalid_cursor}
  def decode(cursor) do
    case Cursor.decode(cursor, @types) do
      {:ok, [inserted_at, id]} -> {:ok, {inserted_at, id}}
      {:error, :invalid_cursor} -> {:error, :invalid_cursor}
    end
  end
end
