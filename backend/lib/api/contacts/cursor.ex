defmodule Api.Contacts.Cursor do
  @moduledoc """
  Cursor for one contact's position in an owner's list.

  The list is ordered by folded display name, then by the contacted user's id,
  and a cursor carries both. The name alone is not enough — display names are
  not unique, and a bound that cannot break the tie skips every row sharing the
  boundary name.

  The name carried is the *folded* one, `lower(immutable_unaccent(name))`, the
  expression the query sorts by; carrying the raw name would compare against a
  different ordering and lose rows at exactly the accented and capitalized names
  the fold exists to place correctly.

  `Api.Cursor` owns the encoding and strictness; only the ordering columns
  belong here.
  """

  alias Api.Contacts.Contact
  alias Api.Cursor

  @typedoc "The `(folded_name, user_id)` pair a cursor encodes."
  @type position :: {String.t(), Ecto.UUID.t()}

  @types [:string, :uuid]

  @doc """
  The opaque position of one contact entry.
  """
  @spec encode(Contact.t() | position()) :: String.t()
  def encode(%Contact{user: %{name: name, id: id}}), do: encode({fold(name), id})

  def encode({sort_name, id}) when is_binary(sort_name), do: Cursor.encode([sort_name, id])

  @doc """
  Reads a cursor back into the pair the keyset query bounds on, or
  `{:error, :invalid_cursor}` if any step of it fails.
  """
  @spec decode(term()) :: {:ok, position()} | {:error, :invalid_cursor}
  def decode(cursor) do
    case Cursor.decode(cursor, @types) do
      {:ok, [sort_name, id]} -> {:ok, {sort_name, id}}
      {:error, :invalid_cursor} -> {:error, :invalid_cursor}
    end
  end

  # Mirrors `lower(immutable_unaccent(name))` in Elixir. `String.downcase/1` and
  # Postgres `lower()` agree on the alphabets this product accepts, and the
  # accent stripping is done by decomposing and dropping the combining marks
  # rather than by a table, so a name is folded the same way on both sides.
  defp fold(name) do
    name
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036F}]/u, "")
    |> String.downcase()
  end
end
