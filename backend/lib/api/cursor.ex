defmodule Api.Cursor do
  @moduledoc """
  Shared encoding for every keyset pagination cursor.

  A cursor holds one row's ordering columns, joined by a separator and
  base64url-encoded without padding, so it travels in a query string unescaped
  and free of `=`, `+` and `/`. Message history, the conversation inbox and the
  contact list each paginate this way and differ only in which columns order
  them; that difference lives in each context, while the encoding, the
  strictness and the failure mode live here.

  Cursors are opaque but deliberately unsigned — they are not capabilities.
  Authorization decides which rows the caller may read before a cursor is
  decoded, so a forged value can only skip content the caller was already
  allowed to see. Signing would duplicate an access-control property the
  authorization layer already owns and would invalidate in-flight cursors on
  every secret rotation.

  Decoding is strict at every step and collapses every failure into
  `{:error, :invalid_cursor}`, so a malformed cursor is never mistaken for an
  absent one; falling back to the first page would silently re-serve content the
  client already holds.

  ## Component types

  A component is declared by type. `:datetime` and `:uuid` must be present;
  `{:nullable, type}` also accepts an absent value, which lets the inbox encode
  a never-used conversation without inventing a timestamp for it.
  """

  @typedoc "What one cursor component holds."
  @type component_type :: :datetime | :uuid | :string | :integer | {:nullable, component_type()}

  @typedoc "A decoded component."
  @type component :: DateTime.t() | Ecto.UUID.t() | String.t() | integer() | nil

  @separator "|"
  @absent "-"

  @doc """
  Encodes ordering `components`, in the order they sort by, into an opaque
  cursor string.

  ## Parameters

    * `components` — the row's ordering values, as a list

  ## Examples

      iex> Api.Cursor.encode([~U[2026-07-24 12:00:00Z], "2b8c9f1e-..."])
      "MjAyNi0wNy0yNFQxMjowMDowMFp8MmI4YzlmMWUtLi4u"
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
  Decodes a cursor into the components described by `types`.

  ## Parameters

    * `cursor` — an opaque cursor string produced by `encode/1`
    * `types` — the component types the list orders by (see the module doc)

  Returns `{:ok, components}`, or `{:error, :invalid_cursor}` if any step fails.
  A component count that does not match `types` also fails — that is what a
  cursor minted for a different list looks like.

  ## Examples

      iex> Api.Cursor.decode(cursor, [:datetime, :uuid])
      {:ok, [~U[2026-07-24 12:00:00Z], "2b8c9f1e-..."]}

      iex> Api.Cursor.decode("garbage", [:datetime, :uuid])
      {:error, :invalid_cursor}
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
  Decodes an optional cursor.

  ## Parameters

    * `cursor` — the raw cursor value, possibly `nil` or `""`
    * `decode` — a one-arity function decoding a present cursor

  Treats `nil` and `""` as "no cursor" and returns `{:ok, nil}`; delegates any
  other value to `decode`. An absent cursor opens the newest page, and only a
  present-but-malformed one is an error.

  ## Examples

      iex> Api.Cursor.decode_or_nil(nil, &Api.Messages.Cursor.decode/1)
      {:ok, nil}

      iex> Api.Cursor.decode_or_nil("garbage", &Api.Messages.Cursor.decode/1)
      {:error, :invalid_cursor}
  """
  @spec decode_or_nil(term(), (String.t() -> {:ok, term()} | {:error, :invalid_cursor})) ::
          {:ok, term() | nil} | {:error, :invalid_cursor}
  def decode_or_nil(cursor, _decode) when cursor in [nil, ""], do: {:ok, nil}
  def decode_or_nil(cursor, decode) when is_function(decode, 1), do: decode.(cursor)

  @doc """
  Clamps a requested page size into `1..max`.

  ## Parameters

    * `limit` — the requested page size, possibly absent or non-integer
    * `default` — the size to use when `limit` is absent or non-integer
    * `max` — the ceiling

  Falls back to `default` for an absent or non-integer value. The bound sits
  next to the cursor because the two form one paging contract; only `default`
  and `max` vary between lists.

  ## Examples

      iex> Api.Cursor.normalize_limit(500, 30, 100)
      100

      iex> Api.Cursor.normalize_limit(nil, 30, 100)
      30
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

  # `Ecto.UUID.cast/1` already returns the `{:ok, uuid} | :error` shape a
  # component decoder owes.
  defp decode_component(part, :uuid), do: Ecto.UUID.cast(part)

  defp decode_component(part, :integer) do
    case Integer.parse(part) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  # An empty string is rejected: it would sort before every row and quietly
  # restart the list.
  defp decode_component("", :string), do: :error
  defp decode_component(part, :string), do: {:ok, part}
end
