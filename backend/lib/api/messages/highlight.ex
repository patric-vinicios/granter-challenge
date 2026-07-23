defmodule Api.Messages.Highlight do
  @moduledoc """
  Where a search term sits inside a message body, as grapheme spans the client
  can highlight without re-matching.

  The search itself resolves through a `tsvector` in the database, but the
  database answers *which* rows matched, not *where* in each body the term lies.
  Recovering that here keeps `match_offsets` a plain data contract — a start and
  a length per occurrence — rather than the markup `ts_headline` would hand back
  for the client to parse.

  Matching mirrors the index's accent- and case-insensitivity: the body and each
  whitespace-delimited query token are normalised the same way — downcased and
  stripped of diacritics — and compared grapheme by grapheme. Normalisation is
  treated as grapheme-preserving, so an offset into the normalised body is an
  offset into the original, and `Família` is highlighted whole for the query
  `familia`. Highlighting is verbatim-token substring matching, not stemmer
  spans: it marks the term the caller typed, not every word that shares its stem.
  """

  @doc """
  The `%{start, length}` grapheme spans of each whitespace-delimited token of
  `query` found in `body`, one entry per occurrence, ordered by position.

  `start` is a 0-based grapheme offset into `body`; `length` counts graphemes.
  Returns `[]` when no token occurs.
  """
  def offsets(body, query) when is_binary(body) and is_binary(query) do
    normalized_body = normalize_graphemes(body)
    tokens = query |> String.split(~r/\s+/u, trim: true) |> Enum.map(&normalize_graphemes/1)

    tokens
    |> Enum.reject(&(&1 == []))
    |> Enum.flat_map(&find_all(normalized_body, &1))
    |> Enum.sort_by(& &1.start)
  end

  # Each grapheme mapped to its normalised form, so index i in this list is
  # index i in the original body — the invariant that lets a match position
  # stand in for an original offset.
  defp normalize_graphemes(string) do
    string |> String.graphemes() |> Enum.map(&normalize/1)
  end

  defp normalize(grapheme) do
    grapheme
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[\x{0300}-\x{036F}]/u, "")
  end

  # Slides the token over the body one grapheme at a time; every window that
  # equals the token is one occurrence. A token longer than the body yields
  # nothing.
  defp find_all(body, token) do
    span = length(token)

    0..(length(body) - span)//1
    |> Enum.filter(fn start -> Enum.slice(body, start, span) == token end)
    |> Enum.map(&%{start: &1, length: span})
  end
end
