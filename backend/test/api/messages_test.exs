defmodule Api.MessagesTest do
  use Api.DataCase, async: true

  alias Api.Conversations
  alias Api.Messages
  alias Api.Messages.Message

  setup do
    ana = insert(:user, name: "Ana Beatriz")
    carlos = insert(:user, name: "Carlos Eduardo")
    outsider = insert(:user, name: "João Pedro")
    conversation = private_conversation(ana, carlos)

    %{ana: ana, carlos: carlos, outsider: outsider, conversation: conversation}
  end

  defp count, do: Repo.aggregate(Message, :count)

  # A group owned by `creator` with `members` seated alongside them.
  defp group_with(creator, members) do
    group = insert(:conversation, type: :group, name: "Time de Produto", creator: creator)
    for user <- [creator | members], do: insert(:participant, conversation: group, user: user)

    group
  end

  # Seeds `n` messages one microsecond apart, oldest first, so the keyset order
  # is deterministic no matter how fast the inserts run.
  defp seed(conversation, sender, n) do
    base = DateTime.utc_now() |> DateTime.add(-n, :second)

    for i <- 1..n do
      {:ok, message} =
        Messages.create_message(sender, conversation.id, %{
          body: "message #{i}",
          inserted_at: DateTime.add(base, i, :second)
        })

      message
    end
  end

  describe "create_message/3" do
    test "persists a message from an active participant", %{ana: ana, conversation: thread} do
      assert {:ok, message} = Messages.create_message(ana, thread.id, %{body: "bom dia"})

      stored = Repo.get!(Message, message.id)
      assert stored.body == "bom dia"
      assert stored.conversation_id == thread.id
      assert stored.sender_id == ana.id
      assert message.sender.id == ana.id
      assert message.sender.username == ana.username
    end

    test "takes the sender from the argument and never from attrs", %{
      ana: ana,
      carlos: carlos,
      conversation: thread
    } do
      assert {:ok, message} =
               Messages.create_message(ana, thread.id, %{body: "oi", sender_id: carlos.id})

      assert Repo.get!(Message, message.id).sender_id == ana.id
    end

    test "accepts a backdated inserted_at on the struct", %{ana: ana, conversation: thread} do
      backdated = ~U[2020-01-01 10:00:00.000000Z]

      assert {:ok, message} =
               Messages.create_message(ana, thread.id, %{body: "antigo", inserted_at: backdated})

      stored = Repo.get!(Message, message.id)
      assert stored.inserted_at == backdated
      assert stored.updated_at == backdated
    end

    test "rejects an empty body", %{ana: ana, conversation: thread} do
      assert {:error, changeset} = Messages.create_message(ana, thread.id, %{body: ""})
      assert errors_on(changeset)[:body]
      assert count() == 0
    end

    test "rejects a whitespace-only body", %{ana: ana, conversation: thread} do
      assert {:error, changeset} = Messages.create_message(ana, thread.id, %{body: "   \n "})
      assert errors_on(changeset)[:body]
      assert count() == 0
    end

    test "rejects a 4001-character body", %{ana: ana, conversation: thread} do
      assert {:error, changeset} =
               Messages.create_message(ana, thread.id, %{body: String.duplicate("a", 4001)})

      assert errors_on(changeset)[:body]
      assert count() == 0
    end

    test "accepts a 4000-character body verbatim", %{ana: ana, conversation: thread} do
      body = String.duplicate("a", 4000)

      assert {:ok, message} = Messages.create_message(ana, thread.id, %{body: body})
      assert Repo.get!(Message, message.id).body == body
    end

    test "trims surrounding whitespace", %{ana: ana, conversation: thread} do
      assert {:ok, message} = Messages.create_message(ana, thread.id, %{body: "  oi  "})
      assert Repo.get!(Message, message.id).body == "oi"
    end

    test "rejects a send from a non-participant", %{outsider: outsider, conversation: thread} do
      assert Messages.create_message(outsider, thread.id, %{body: "oi"}) == {:error, :not_found}
      assert count() == 0
    end

    test "rejects a send from a departed group member", %{ana: ana, carlos: carlos} do
      group = group_with(ana, [carlos])

      assert {:ok, _} = Messages.create_message(carlos, group.id, %{body: "ainda estou aqui"})
      assert :ok = Conversations.remove_member(ana, group.id, carlos.id)

      assert Messages.create_message(carlos, group.id, %{body: "e agora"}) ==
               {:error, :not_found}

      assert count() == 1
    end

    test "rejects a send to an unknown conversation", %{ana: ana} do
      assert Messages.create_message(ana, Ecto.UUID.generate(), %{body: "oi"}) ==
               {:error, :not_found}
    end

    test "rejects a malformed conversation id", %{ana: ana} do
      assert Messages.create_message(ana, "not-a-uuid", %{body: "oi"}) == {:error, :invalid_id}
    end
  end

  describe "list_messages/3" do
    test "returns the newest page in ascending order", %{
      ana: ana,
      carlos: carlos,
      conversation: thread
    } do
      seeded = seed(thread, ana, 50)

      assert {:ok, page} = Messages.list_messages(carlos, thread.id)
      assert Enum.count(page.messages) == 30
      assert page.has_more
      assert page.next_cursor

      bodies = Enum.map(page.messages, & &1.body)
      assert bodies == Enum.map(21..50, &"message #{&1}")
      assert List.last(page.messages).id == List.last(seeded).id
    end

    test "returns an empty page for a conversation with no messages", %{
      ana: ana,
      conversation: thread
    } do
      assert {:ok, %{messages: [], next_cursor: nil, has_more: false}} =
               Messages.list_messages(ana, thread.id)
    end

    test "paginates a 250-message conversation exactly once", %{ana: ana, conversation: thread} do
      seeded = seed(thread, ana, 250)
      expected = Enum.map(seeded, & &1.id)

      collected = walk(ana, thread, nil, [])

      assert Enum.count(collected) == 250
      assert Enum.sort(collected) == Enum.sort(expected)
      assert collected == expected
    end

    test "reports has_more false exactly on the oldest page", %{ana: ana, conversation: thread} do
      seed(thread, ana, 65)

      flags = walk_flags(ana, thread, nil, [])

      assert flags == [true, true, false]
    end

    test "reports has_more false when the page holds every message", %{
      ana: ana,
      conversation: thread
    } do
      seed(thread, ana, 30)

      assert {:ok, page} = Messages.list_messages(ana, thread.id)
      assert Enum.count(page.messages) == 30
      refute page.has_more
      refute page.next_cursor
    end

    test "is stable across concurrent inserts", %{ana: ana, conversation: thread} do
      seed(thread, ana, 40)

      assert {:ok, first} = Messages.list_messages(ana, thread.id, %{limit: 10})

      arrivals = seed(thread, ana, 5) |> Enum.map(& &1.id)

      assert {:ok, second} =
               Messages.list_messages(ana, thread.id, %{limit: 10, before: first.next_cursor})

      first_ids = Enum.map(first.messages, & &1.id)
      second_ids = Enum.map(second.messages, & &1.id)

      assert first_ids -- second_ids == first_ids
      assert Enum.uniq(first_ids ++ second_ids) == first_ids ++ second_ids
      assert Enum.all?(arrivals, &(&1 not in first_ids and &1 not in second_ids))
    end

    test "caps and defaults the limit", %{ana: ana, conversation: thread} do
      seed(thread, ana, 120)

      assert {:ok, %{messages: default}} = Messages.list_messages(ana, thread.id)
      assert {:ok, %{messages: one}} = Messages.list_messages(ana, thread.id, %{limit: 1})
      assert {:ok, %{messages: hundred}} = Messages.list_messages(ana, thread.id, %{limit: 100})

      assert Enum.count(default) == 30
      assert Enum.count(one) == 1
      assert Enum.count(hundred) == 100
    end

    test "rejects a malformed cursor", %{ana: ana, conversation: thread} do
      seed(thread, ana, 5)

      assert Messages.list_messages(ana, thread.id, %{before: "!!!"}) ==
               {:error, :invalid_cursor}
    end

    test "rejects a history read from a non-participant", %{
      ana: ana,
      outsider: outsider,
      conversation: thread
    } do
      seed(thread, ana, 3)

      assert Messages.list_messages(outsider, thread.id) == {:error, :not_found}
    end

    test "rejects a history read of an unknown conversation", %{ana: ana} do
      assert Messages.list_messages(ana, Ecto.UUID.generate()) == {:error, :not_found}
    end

    test "rejects a malformed conversation id", %{ana: ana} do
      assert Messages.list_messages(ana, "nope") == {:error, :invalid_id}
    end

    test "bounds a departed group member at left_at", %{ana: ana, carlos: carlos} do
      group = group_with(ana, [carlos])

      before_removal = seed(group, ana, 3) |> Enum.map(& &1.id)
      assert :ok = Conversations.remove_member(ana, group.id, carlos.id)

      after_removal =
        for i <- 1..40 do
          {:ok, message} = Messages.create_message(ana, group.id, %{body: "depois #{i}"})
          message.id
        end

      assert {:ok, page} = Messages.list_messages(carlos, group.id, %{limit: 2})
      assert Enum.count(page.messages) == 2
      assert page.has_more

      assert {:ok, older} =
               Messages.list_messages(carlos, group.id, %{limit: 2, before: page.next_cursor})

      seen = Enum.map(page.messages ++ older.messages, & &1.id)
      assert Enum.sort(seen) == Enum.sort(before_removal)
      refute older.has_more
      assert Enum.all?(after_removal, &(&1 not in seen))
    end

    test "preloads the sender on every message", %{
      ana: ana,
      carlos: carlos,
      conversation: thread
    } do
      seed(thread, ana, 2)
      seed(thread, carlos, 2)

      assert {:ok, page} = Messages.list_messages(ana, thread.id)

      assert Enum.all?(page.messages, fn message ->
               match?(%Api.Accounts.User{username: _, name: _}, message.sender)
             end)
    end
  end

  # Follows `next_cursor` to exhaustion, accumulating ids in chronological order.
  defp walk(user, thread, cursor, acc) do
    opts = if cursor, do: %{before: cursor}, else: %{}
    {:ok, page} = Messages.list_messages(user, thread.id, opts)
    acc = Enum.map(page.messages, & &1.id) ++ acc

    if page.has_more, do: walk(user, thread, page.next_cursor, acc), else: acc
  end

  defp walk_flags(user, thread, cursor, acc) do
    opts = if cursor, do: %{before: cursor}, else: %{}
    {:ok, page} = Messages.list_messages(user, thread.id, opts)
    acc = acc ++ [page.has_more]

    if page.has_more, do: walk_flags(user, thread, page.next_cursor, acc), else: acc
  end
end
