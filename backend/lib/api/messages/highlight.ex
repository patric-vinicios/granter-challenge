defmodule Api.Messages.Highlight do
  @moduledoc """
  Turns a Postgres `ts_headline` marked string into `{start, length}` grapheme
  spans, so a client highlights exactly the lexemes the search matched —
  including stemmed and accent-folded forms — without re-running the match.
  """

  @typedoc "One matched span: a 0-based grapheme offset into the body and a grapheme count."
  @type span :: %{start: non_neg_integer(), length: pos_integer()}

  # Control characters that cannot occur in a chat body, so they delimit matches
  # unambiguously and never advance a position in the original text.
  @start "\x02"
  @stop "\x03"

  @doc "The marker options passed to `ts_headline`."
  @spec headline_opts() :: String.t()
  def headline_opts, do: "StartSel=#{@start},StopSel=#{@stop},HighlightAll=TRUE,MaxFragments=0"

  @doc """
  Parses the markers `ts_headline` inserted into `headline`, returning the
  grapheme spans of each highlight in the order they appear.

  ## Parameters

    * `headline` — a `ts_headline` result string, or `nil`

  ## Examples

      iex> Api.Messages.Highlight.offsets_from_headline("Eu \\x02corri\\x03 ontem")
      [%{start: 3, length: 5}]

      iex> Api.Messages.Highlight.offsets_from_headline(nil)
      []
  """
  @spec offsets_from_headline(String.t() | nil) :: [span()]
  def offsets_from_headline(nil), do: []

  def offsets_from_headline(headline) when is_binary(headline) do
    headline
    |> String.graphemes()
    |> Enum.reduce({[], 0, nil}, fn
      @start, {spans, pos, _open} -> {spans, pos, pos}
      @stop, {spans, pos, open} -> {[%{start: open, length: pos - open} | spans], pos, nil}
      _grapheme, {spans, pos, open} -> {spans, pos + 1, open}
    end)
    |> elem(0)
    |> Enum.reverse()
  end
end
