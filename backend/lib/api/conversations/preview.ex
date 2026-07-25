defmodule Api.Conversations.Preview do
  @moduledoc """
  The last-message preview rule for the conversation inbox.

  Truncation is part of what the conversations context provides, not a rendering
  concern: the inbox entry and the filtered search list return the same shape, so
  the rule lives here with one home and its own unit tests, the way
  `Api.Messages.Cursor` sits beside the messages boundary. The stored body is
  untouched — the history endpoint returns it verbatim, and this applies to the
  preview alone.

  Whitespace runs, newlines included, collapse to a single space before length is
  measured. A body within the limit is returned as-is; a longer one is cut at the
  last word boundary that fits, falling back to a hard cut when the first word
  already exceeds the limit, and a single-character ellipsis is appended. The
  result is never longer than the limit, counting the ellipsis.
  """

  @limit 120
  @ellipsis "…"
  @body_limit @limit - String.length(@ellipsis)

  @doc """
  Collapses whitespace and truncates `body` to at most 120 graphemes including
  the ellipsis.

  ## Parameters

    * `body` — the raw message body

  ## Examples

      iex> Api.Conversations.Preview.truncate("Oi!   Tudo\\nbem?")
      "Oi! Tudo bem?"
  """
  @spec truncate(String.t()) :: String.t()
  def truncate(body) when is_binary(body) do
    collapsed = body |> String.replace(~r/\s+/u, " ") |> String.trim()

    if String.length(collapsed) <= @limit do
      collapsed
    else
      collapsed |> cut() |> Kernel.<>(@ellipsis)
    end
  end

  defp cut(collapsed) do
    head = String.slice(collapsed, 0, @body_limit)
    next = String.at(collapsed, @body_limit)

    cond do
      next == " " -> String.trim_trailing(head)
      String.contains?(head, " ") -> head |> word_prefix() |> String.trim_trailing()
      true -> head
    end
  end

  defp word_prefix(head) do
    head |> String.split(" ") |> Enum.drop(-1) |> Enum.join(" ")
  end
end
