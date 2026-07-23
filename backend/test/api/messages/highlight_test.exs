defmodule Api.Messages.HighlightTest do
  use ExUnit.Case, async: true

  alias Api.Messages.Highlight

  describe "offsets/2" do
    test "returns the offset of a plain term" do
      assert Highlight.offsets("O cronograma novo", "cronograma") == [%{start: 2, length: 10}]
    end

    test "matches accent- and case-insensitively" do
      assert Highlight.offsets("Reunião da Família amanhã", "familia") == [
               %{start: 11, length: 7}
             ]
    end

    test "returns an offset per occurrence" do
      assert Highlight.offsets("bug aqui e bug ali", "bug") == [
               %{start: 0, length: 3},
               %{start: 11, length: 3}
             ]
    end

    test "handles multi-token queries" do
      offsets = Highlight.offsets("novo cronograma final", "novo final")

      assert %{start: 0, length: 4} in offsets
      assert %{start: 16, length: 5} in offsets
      assert length(offsets) == 2
    end

    test "returns an empty list when nothing matches" do
      assert Highlight.offsets("nada por aqui", "cronograma") == []
    end

    test "returns an empty list for a blank query" do
      assert Highlight.offsets("qualquer corpo", "   ") == []
    end
  end
end
