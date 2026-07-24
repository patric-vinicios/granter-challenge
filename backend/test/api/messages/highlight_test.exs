defmodule Api.Messages.HighlightTest do
  use ExUnit.Case, async: true

  alias Api.Messages.Highlight

  @start "\x02"
  @stop "\x03"

  defp mark(text),
    do:
      String.replace(text, ["[", "]"], fn
        "[" -> @start
        "]" -> @stop
      end)

  describe "offsets_from_headline/1" do
    test "returns the span of a single highlight" do
      assert Highlight.offsets_from_headline(mark("O [cronograma] novo")) == [
               %{start: 2, length: 10}
             ]
    end

    test "returns a span per highlight, in order" do
      assert Highlight.offsets_from_headline(mark("[bug] aqui e [bug] ali")) == [
               %{start: 0, length: 3},
               %{start: 11, length: 3}
             ]
    end

    test "measures offsets in the original text, not counting markers" do
      assert Highlight.offsets_from_headline(mark("Reunião da [Família] amanhã")) == [
               %{start: 11, length: 7}
             ]
    end

    test "returns an empty list when nothing is highlighted" do
      assert Highlight.offsets_from_headline("nada por aqui") == []
    end

    test "returns an empty list for a nil headline" do
      assert Highlight.offsets_from_headline(nil) == []
    end
  end

  describe "headline_opts/0" do
    test "declares the control-character markers to ts_headline" do
      assert Highlight.headline_opts() =~ "HighlightAll=TRUE"
      assert Highlight.headline_opts() =~ @start
      assert Highlight.headline_opts() =~ @stop
    end
  end
end
