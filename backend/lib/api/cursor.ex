defmodule Api.Cursor do
  @moduledoc """
  The encoding every keyset cursor in the system shares.

  A cursor is the ordering columns of one row, joined by a separator and
  base64url-encoded without padding, so it survives a query string without
  escaping and carries no `=`, `+` or `/`. Three lists are paginated this way —
  message history, the conversation inbox and the contact list — and they differ
  only in which columns order them. That difference belongs to each context;
  the escaping, the strictness and the failure mode do not, and keeping one copy
  of them is what stops the three from drifting into three slightly different
  notions of a malformed cursor.

  A cursor is opaque but deliberately not signed, and the distinction matters:
  it is not a capability. By the time one is decoded, authorization has already
  decided which rows the caller may read; the cursor only chooses where inside
  that set to start, so a forged value can do no more than skip content the
  caller was always allowed to see. Signing would buy an access-control property
  the authorization layer already owns, at the price of invalidating every
  in-flight cursor whenever the secret rotates.

  Decoding is strict at every step and collapses each failure into one error, so
  no distinction between failure modes is observable and a malformed cursor can
  never be mistaken for an absent one. Falling back to the first page would hand
  a client a duplicate of content it already holds, with no way to notice.

  A component is declared by type. `:datetime` and `:uuid` must be present;
  `{:nullable, type}` also accepts an absent value, which is what lets the inbox
  encode a conversation that has never been used without inventing a timestamp
  for it.
  """

  @typedoc "What one cursor component holds."
  @type component_type :: :datetime | :uuid | :string | :integer | {:nullable, component_type()}

  @typedoc "A decoded component."
  @type component :: DateTime.t() | Ecto.UUID.t() | String.t() | integer() | nil

  @separator "|"
  @absent "-"

  @doc """
  Encodes ordering components, in the order they order by.
  """
  @spec encode([component()]) :: String.t()
  def encode(components) when is_list(components) do
    components
    |> Enum.map_join(@separator, &encode_component/1)
    |> Base.url_encode64(padding: false)
  end

  defp encode_component(nil), do: @absent
  defp encode_component(%DateTime{} = at), do: DateTime.to_iso8601(at)
  defp encode_component(value) when is_integer(value), do: Integer.to_string(value)
  defp encode_component(value) when is_binary(value), do: value

  @doc """
  Reads a cursor back into the components `types` describes, or
  `{:error, :invalid_cursor}` if any step of it fails — including a cursor whose
  component count does not match the list it is being read for, which is what a
  cursor minted for a different list looks like.
  """
  @spec decode(term(), [component_type()]) :: {:ok, [component()]} | {:error, :invalid_cursor}
  def decode(cursor, types) when is_binary(cursor) and is_list(types) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         parts = String.split(raw, @separator),
         true <- Enum.count(parts) == Enum.count(types),
         {:ok, components} <- decode_components(parts, types) do
      {:ok, components}
    else
      _ -> {:error, :invalid_cursor}
    end
  end

  def decode(_cursor, _types), do: {:error, :invalid_cursor}

  @doc """
  Treats `nil` and `""` as "no cursor" and delegates any other value to the
  list's own `decode` function.

  Every paginated list shares this nil-or-decode step: an absent cursor opens the
  newest page, and only a present-but-malformed one is an error. Keeping the
  branch here stops the three lists from drifting into three slightly different
  notions of "no cursor".
  """
  @spec decode_or_nil(term(), (String.t() -> {:ok, term()} | {:error, :invalid_cursor})) ::
          {:ok, term() | nil} | {:error, :invalid_cursor}
  def decode_or_nil(cursor, _decode) when cursor in [nil, ""], do: {:ok, nil}
  def decode_or_nil(cursor, decode) when is_function(decode, 1), do: decode.(cursor)

  @doc """
  Clamps a requested page size into `1..max`, falling back to `default` for an
  absent or non-integer value.

  The bound belongs next to the cursor because the two are one paging contract:
  what differs between the lists is only `default` and `max`, not the clamping.
  """
  @spec normalize_limit(term(), pos_integer(), pos_integer()) :: pos_integer()
  def normalize_limit(nil, default, _max), do: default
  def normalize_limit(limit, _default, _max) when is_integer(limit) and limit < 1, do: 1
  def normalize_limit(limit, _default, max) when is_integer(limit) and limit > max, do: max
  def normalize_limit(limit, _default, _max) when is_integer(limit), do: limit
  def normalize_limit(_limit, default, _max), do: default

  defp decode_components(parts, types) do
    parts
    |> Enum.zip(types)
    |> Enum.reduce_while({:ok, []}, fn {part, type}, {:ok, acc} ->
      case decode_component(part, type) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      :error -> :error
    end
  end

  defp decode_component(@absent, {:nullable, _type}), do: {:ok, nil}
  defp decode_component(part, {:nullable, type}), do: decode_component(part, type)

  defp decode_component(part, :datetime) do
    case DateTime.from_iso8601(part) do
      {:ok, at, 0} -> {:ok, at}
      _ -> :error
    end
  end

  # `Ecto.UUID.cast/1` already answers in exactly the shape a component decoder
  # owes: `{:ok, uuid}` or `:error`.
  defp decode_component(part, :uuid), do: Ecto.UUID.cast(part)

  defp decode_component(part, :integer) do
    case Integer.parse(part) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  # A string component orders rows but names nothing, so the only thing that can
  # be wrong with it is being empty — an empty ordering key would compare before
  # every row and quietly restart the list.
  defp decode_component("", :string), do: :error
  defp decode_component(part, :string), do: {:ok, part}
end
