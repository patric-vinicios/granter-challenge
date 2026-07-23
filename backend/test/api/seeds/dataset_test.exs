defmodule Api.Seeds.DatasetTest do
  use ExUnit.Case, async: true

  alias Api.Seeds.Dataset

  @dataset Dataset.all()
  @anchor ~U[2026-07-23 12:00:00.000000Z]

  defp resolve({days_ago, minutes_back}) do
    @anchor
    |> DateTime.add(-days_ago, :day)
    |> DateTime.add(-minutes_back, :minute)
  end

  defp members(%{kind: :private, with: counterpart}), do: [@dataset.primary, counterpart]
  defp members(%{kind: :group, members: members}), do: members

  test "declares seven users including the primary account" do
    usernames = Enum.map(@dataset.users, & &1.username)

    assert Enum.count(@dataset.users) == 7
    assert Enum.uniq(usernames) == usernames
    assert @dataset.primary in usernames
  end

  test "declares four private and two group conversations" do
    assert Enum.frequencies_by(@dataset.conversations, & &1.kind) == %{private: 4, group: 2}
  end

  test "declares at least sixty messages" do
    total = @dataset.conversations |> Enum.map(&length(&1.messages)) |> Enum.sum()

    assert total >= 60
  end

  test "offsets are strictly increasing within every conversation" do
    for conversation <- @dataset.conversations do
      conversation.messages
      |> Enum.map(fn {_sender, _body, offset} -> resolve(offset) end)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [earlier, later] ->
        assert DateTime.compare(earlier, later) == :lt
      end)
    end
  end

  test "no offset resolves into the future" do
    for conversation <- @dataset.conversations,
        {_sender, _body, offset} <- conversation.messages do
      assert DateTime.compare(resolve(offset), @anchor) in [:lt, :eq]
    end
  end

  test "every body satisfies the message length bounds" do
    for conversation <- @dataset.conversations,
        {_sender, body, _offset} <- conversation.messages do
      trimmed = String.trim(body)
      assert String.length(trimmed) >= 1
      assert String.length(trimmed) <= 4000
    end
  end

  test "every sender is a member of its conversation" do
    for conversation <- @dataset.conversations,
        {sender, _body, _offset} <- conversation.messages do
      assert sender in members(conversation)
    end
  end

  test "spans today, yesterday and the previous week" do
    days =
      for conversation <- @dataset.conversations,
          {_sender, _body, {days_ago, _minutes}} <- conversation.messages,
          uniq: true,
          do: days_ago

    assert 0 in days
    assert 1 in days
    assert Enum.any?(days, &(&1 >= 7))
  end

  test "unread declarations name only messages from other senders" do
    for conversation <- @dataset.conversations, conversation.unread > 0 do
      trailing = Enum.take(conversation.messages, -conversation.unread)

      for {sender, _body, _offset} <- trailing do
        refute sender == @dataset.primary
      end
    end
  end

  test "both groups record a creator that is one of their members" do
    for conversation <- @dataset.conversations, conversation.kind == :group do
      assert conversation.creator in conversation.members
    end
  end
end
