defmodule Api.Messages.CursorTest do
  use ExUnit.Case, async: true

  alias Api.Messages.Cursor
  alias Api.Messages.Message

  defp message(inserted_at \\ ~U[2026-07-22 13:48:17.123456Z]) do
    %Message{id: "3a1d0c74-8e5b-4a11-9c22-5b7c1f2d3e40", inserted_at: inserted_at}
  end

  defp encoded(raw), do: Base.url_encode64(raw, padding: false)

  describe "encode/1 and decode/1" do
    test "round trips a message, preserving microseconds" do
      message = message()

      assert {:ok, {inserted_at, id}} = message |> Cursor.encode() |> Cursor.decode()
      assert inserted_at == message.inserted_at
      assert inserted_at.microsecond == {123_456, 6}
      assert id == message.id
    end

    test "produces a URL-safe value" do
      cursor = Cursor.encode(message())

      refute String.contains?(cursor, "=")
      refute String.contains?(cursor, "+")
      refute String.contains?(cursor, "/")
    end

    test "encodes a bare pair the same way it encodes a message" do
      message = message()

      assert Cursor.encode({message.inserted_at, message.id}) == Cursor.encode(message)
    end
  end

  describe "decode/1 failures" do
    test "rejects a non-base64 value" do
      assert Cursor.decode("!!!") == {:error, :invalid_cursor}
    end

    test "rejects a value missing the separator" do
      assert Cursor.decode(encoded("2026-07-22T13:48:17.123456Z")) == {:error, :invalid_cursor}
    end

    test "rejects an unparseable timestamp" do
      assert Cursor.decode(encoded("nope|3a1d0c74-8e5b-4a11-9c22-5b7c1f2d3e40")) ==
               {:error, :invalid_cursor}
    end

    test "rejects a timestamp that is not UTC" do
      assert Cursor.decode(encoded("2026-07-22T13:48:17.123456+03:00|" <> message().id)) ==
               {:error, :invalid_cursor}
    end

    test "rejects a non-UUID id" do
      assert Cursor.decode(encoded("2026-07-22T13:48:17.123456Z|nope")) ==
               {:error, :invalid_cursor}
    end

    test "rejects a tampered but well-formed base64 value" do
      cursor = Cursor.encode(message())
      tampered = String.replace(cursor, String.at(cursor, 3), "_", global: false)

      assert Cursor.decode(tampered) == {:error, :invalid_cursor}
    end

    test "rejects a value that is not a string" do
      assert Cursor.decode(nil) == {:error, :invalid_cursor}
    end
  end
end
