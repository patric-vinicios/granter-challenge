defmodule Api.CursorTest do
  use ExUnit.Case, async: true

  alias Api.Cursor

  @at ~U[2026-07-22 13:48:17.123456Z]
  @uuid "3a1d0c74-8e5b-4a11-9c22-5b7c1f2d3e40"

  describe "encode/1 and decode/2" do
    test "round trips a datetime and a uuid, preserving microseconds" do
      assert {:ok, [at, id]} =
               [@at, @uuid] |> Cursor.encode() |> Cursor.decode([:datetime, :uuid])

      assert at == @at
      assert at.microsecond == {123_456, 6}
      assert id == @uuid
    end

    test "round trips a string component" do
      assert {:ok, ["ana beatriz", @uuid]} =
               ["ana beatriz", @uuid] |> Cursor.encode() |> Cursor.decode([:string, :uuid])
    end

    test "round trips an absent nullable component" do
      assert {:ok, [nil, @at, @uuid]} =
               [nil, @at, @uuid]
               |> Cursor.encode()
               |> Cursor.decode([{:nullable, :datetime}, :datetime, :uuid])
    end

    test "round trips a present nullable component" do
      assert {:ok, [activity, _at, _id]} =
               [@at, @at, @uuid]
               |> Cursor.encode()
               |> Cursor.decode([{:nullable, :datetime}, :datetime, :uuid])

      assert activity == @at
    end

    test "produces a URL-safe value" do
      cursor = Cursor.encode([@at, @uuid])

      refute String.contains?(cursor, "=")
      refute String.contains?(cursor, "+")
      refute String.contains?(cursor, "/")
    end
  end

  describe "decode/2 failures" do
    test "rejects a non-base64 value" do
      assert Cursor.decode("!!!", [:datetime, :uuid]) == {:error, :invalid_cursor}
    end

    test "rejects a value that is not a string" do
      for value <- [nil, 42, %{}, ["a"]] do
        assert Cursor.decode(value, [:datetime, :uuid]) == {:error, :invalid_cursor}
      end
    end

    test "rejects a cursor carrying the wrong number of components" do
      cursor = Cursor.encode([@at, @uuid])

      assert Cursor.decode(cursor, [:datetime, :datetime, :uuid]) == {:error, :invalid_cursor}
      assert Cursor.decode(cursor, [:uuid]) == {:error, :invalid_cursor}
    end

    test "rejects a malformed datetime" do
      cursor = Cursor.encode(["not-a-date", @uuid])

      assert Cursor.decode(cursor, [:datetime, :uuid]) == {:error, :invalid_cursor}
    end

    test "rejects a datetime carrying an offset other than UTC" do
      cursor = Base.url_encode64("2026-07-22T13:48:17.123456+02:00|#{@uuid}", padding: false)

      assert Cursor.decode(cursor, [:datetime, :uuid]) == {:error, :invalid_cursor}
    end

    test "rejects a malformed uuid" do
      cursor = Cursor.encode([@at, "not-a-uuid"])

      assert Cursor.decode(cursor, [:datetime, :uuid]) == {:error, :invalid_cursor}
    end

    test "rejects an empty string component, which would restart the list" do
      cursor = Cursor.encode(["", @uuid])

      assert Cursor.decode(cursor, [:string, :uuid]) == {:error, :invalid_cursor}
    end

    test "rejects an absent component where the type is not nullable" do
      cursor = Cursor.encode([nil, @uuid])

      assert Cursor.decode(cursor, [:datetime, :uuid]) == {:error, :invalid_cursor}
    end
  end
end
