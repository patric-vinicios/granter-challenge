defmodule Api.Conversations.PreviewTest do
  use ExUnit.Case, async: true

  alias Api.Conversations.Preview

  @ellipsis "…"

  describe "truncate/1" do
    test "returns a short body verbatim" do
      body = "a short message"
      assert Preview.truncate(body) == body
    end

    test "returns a body of exactly the limit verbatim" do
      body = String.duplicate("a", 120)
      assert Preview.truncate(body) == body
      refute String.ends_with?(Preview.truncate(body), @ellipsis)
    end

    test "truncates at the last word boundary" do
      body = String.duplicate("palavra ", 40) |> String.trim()
      result = Preview.truncate(body)

      assert String.length(result) <= 120
      assert String.ends_with?(result, @ellipsis)
      stem = String.trim_trailing(result, @ellipsis)
      refute String.ends_with?(stem, "palavr")
      assert String.contains?(body, String.trim_trailing(stem, " "))
    end

    test "hard-cuts a single word longer than the limit" do
      body = String.duplicate("z", 200)
      result = Preview.truncate(body)

      assert String.length(result) == 120
      assert String.ends_with?(result, @ellipsis)
    end

    test "collapses newlines and repeated spaces" do
      result = Preview.truncate("first\n\nsecond   third")

      assert result == "first second third"
      refute String.contains?(result, "\n")
    end

    test "strips trailing whitespace before the ellipsis" do
      body = String.duplicate("wordword ", 20) |> String.trim()
      result = Preview.truncate(body)

      stem = String.trim_trailing(result, @ellipsis)
      refute String.ends_with?(stem, " ")
    end

    test "counts characters and not bytes" do
      body = String.duplicate("áé ", 60) |> String.trim()
      result = Preview.truncate(body)

      assert String.length(result) <= 120
      assert String.valid?(result)
    end
  end
end
