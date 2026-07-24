defmodule ApiWeb.Conversations.MessageControllerTest do
  use ApiWeb.ConnCase, async: true

  alias Api.Accounts.Guardian
  alias Api.Conversations
  alias Api.Messages

  setup do
    ana = insert(:user, name: "Ana Beatriz")
    carlos = insert(:user, name: "Carlos Eduardo")
    outsider = insert(:user, name: "João Pedro")
    thread = private_conversation(ana, carlos)

    {:ok,
     conn: authenticate(json_conn(), ana),
     ana: ana,
     carlos: carlos,
     outsider: outsider,
     thread: thread}
  end

  defp authenticate(conn, user) do
    {:ok, token, _expires_at} = Guardian.issue_token(user)

    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  # Seeds `n` messages one second apart, oldest first, so the order the endpoint
  # returns is deterministic regardless of how fast the inserts run.
  defp seed(conversation, sender, n) do
    base = DateTime.utc_now() |> DateTime.add(-n - 60, :second)

    for i <- 1..n do
      {:ok, message} =
        Messages.create_message(sender, conversation.id, %{
          body: "message #{i}",
          inserted_at: DateTime.add(base, i, :second)
        })

      message
    end
  end

  defp history(conn, conversation_id, params \\ %{}) do
    conn
    |> get(~p"/api/conversations/#{conversation_id}/messages", params)
    |> json_response(200)
  end

  defp group_with(creator, members) do
    group = insert(:conversation, type: :group, name: "Time de Produto", creator: creator)
    for user <- [creator | members], do: insert(:participant, conversation: group, user: user)

    group
  end

  describe "GET /api/conversations/:id/messages" do
    test "returns the newest 30 messages ascending without a cursor", %{
      conn: conn,
      ana: ana,
      thread: thread
    } do
      seed(thread, ana, 50)

      assert %{"messages" => messages, "has_more" => true, "next_cursor" => cursor} =
               history(conn, thread.id)

      assert Enum.count(messages) == 30
      assert Enum.map(messages, & &1["body"]) == Enum.map(21..50, &"message #{&1}")
      assert is_binary(cursor)

      timestamps = Enum.map(messages, & &1["inserted_at"])
      assert timestamps == Enum.sort(timestamps)
    end

    test "returns a message written through the context in an earlier request", %{
      conn: conn,
      ana: ana,
      thread: thread
    } do
      {:ok, written} = Messages.create_message(ana, thread.id, %{body: "persistida"})

      assert %{"messages" => [message]} = history(conn, thread.id)
      assert message["id"] == written.id
      assert message["body"] == "persistida"
      assert message["conversation_id"] == thread.id
      assert message["inserted_at"] == DateTime.to_iso8601(written.inserted_at)
    end

    test "walks a 250-message conversation without duplicates or gaps", %{
      conn: conn,
      ana: ana,
      thread: thread
    } do
      expected = thread |> seed(ana, 250) |> Enum.map(& &1.id)

      {collected, last_page} = walk(conn, thread, nil, [])

      assert collected == expected
      assert last_page["next_cursor"] == nil
      assert last_page["has_more"] == false
    end

    test "does not duplicate or skip when messages arrive between pages", %{
      conn: conn,
      ana: ana,
      carlos: carlos,
      thread: thread
    } do
      seed(thread, ana, 40)

      first = history(conn, thread.id, %{"limit" => "10"})
      arrivals = thread |> seed(carlos, 3) |> Enum.map(& &1.id)

      second = history(conn, thread.id, %{"limit" => "10", "before" => first["next_cursor"]})

      first_ids = Enum.map(first["messages"], & &1["id"])
      second_ids = Enum.map(second["messages"], & &1["id"])

      assert Enum.uniq(first_ids ++ second_ids) == first_ids ++ second_ids
      assert Enum.all?(arrivals, &(&1 not in first_ids and &1 not in second_ids))
    end

    test "accepts limit=100", %{conn: conn, ana: ana, thread: thread} do
      seed(thread, ana, 120)

      assert %{"messages" => messages} = history(conn, thread.id, %{"limit" => "100"})
      assert Enum.count(messages) == 100
    end

    test "rejects limit=101", %{conn: conn, thread: thread} do
      conn = get(conn, ~p"/api/conversations/#{thread.id}/messages", %{"limit" => "101"})

      assert %{"errors" => %{"code" => "validation_error", "fields" => fields}} =
               json_response(conn, 422)

      assert fields["limit"] == ["must be between 1 and 100"]
    end

    test "rejects limit=0", %{conn: conn, thread: thread} do
      conn = get(conn, ~p"/api/conversations/#{thread.id}/messages", %{"limit" => "0"})

      assert %{"errors" => %{"fields" => %{"limit" => ["must be between 1 and 100"]}}} =
               json_response(conn, 422)
    end

    test "rejects a non-numeric limit", %{conn: conn, thread: thread} do
      conn = get(conn, ~p"/api/conversations/#{thread.id}/messages", %{"limit" => "abc"})

      assert %{"errors" => %{"code" => "validation_error", "fields" => fields}} =
               json_response(conn, 422)

      assert fields["limit"] == ["must be between 1 and 100"]
    end

    test "rejects a tampered cursor without falling back to the newest page", %{
      conn: conn,
      ana: ana,
      thread: thread
    } do
      seed(thread, ana, 5)
      valid = history(conn, thread.id, %{"limit" => "2"})["next_cursor"]
      tampered = String.replace(valid, String.at(valid, 2), "_", global: false)

      conn = get(conn, ~p"/api/conversations/#{thread.id}/messages", %{"before" => tampered})

      body = json_response(conn, 400)

      assert body["errors"]["code"] == "invalid_cursor"
      assert body["errors"]["detail"] == "The pagination cursor is invalid"
      refute Map.has_key?(body, "messages")
    end

    test "rejects a malformed conversation id", %{conn: conn} do
      conn = get(conn, ~p"/api/conversations/nope/messages")

      assert json_response(conn, 400)["errors"]["code"] == "invalid_id"
    end

    test "returns 404 to a non-participant with no message content", %{
      ana: ana,
      outsider: outsider,
      thread: thread
    } do
      seed(thread, ana, 3)

      conn =
        get(authenticate(json_conn(), outsider), ~p"/api/conversations/#{thread.id}/messages")

      body = json_response(conn, 404)

      assert body["errors"]["code"] == "not_found"
      refute Map.has_key?(body, "messages")
    end

    test "returns 404 for an unknown conversation", %{conn: conn} do
      conn = get(conn, ~p"/api/conversations/#{Ecto.UUID.generate()}/messages")

      assert json_response(conn, 404)["errors"]["code"] == "not_found"
    end

    test "requires authentication", %{thread: thread} do
      conn = get(json_conn(), ~p"/api/conversations/#{thread.id}/messages")

      assert json_response(conn, 401)["errors"]["code"] == "unauthenticated"
    end

    test "embeds sender id, username and display name on every message", %{
      conn: conn,
      ana: ana,
      carlos: carlos,
      thread: thread
    } do
      seed(thread, ana, 2)
      seed(thread, carlos, 2)

      assert %{"messages" => messages} = history(conn, thread.id)
      assert Enum.count(messages) == 4

      for message <- messages do
        assert %{"id" => id, "username" => username, "name" => name} = message["sender"]
        assert id in [ana.id, carlos.id]
        assert username in [ana.username, carlos.username]
        assert name in ["Ana Beatriz", "Carlos Eduardo"]
        assert Map.has_key?(message["sender"], "last_seen_at")
      end
    end

    test "returns an empty page for a conversation with no messages", %{
      conn: conn,
      thread: thread
    } do
      assert history(conn, thread.id) == %{
               "messages" => [],
               "next_cursor" => nil,
               "has_more" => false
             }
    end
  end

  describe "cross-feature integration" do
    test "a private conversation carries both participants and refuses a third reader", %{
      conn: conn,
      ana: ana,
      carlos: carlos,
      outsider: outsider,
      thread: thread
    } do
      {:ok, _} = Messages.create_message(ana, thread.id, %{body: "bom dia"})
      {:ok, _} = Messages.create_message(carlos, thread.id, %{body: "bom dia!"})

      carlos_conn = authenticate(json_conn(), carlos)

      for reader_conn <- [conn, carlos_conn] do
        assert %{"messages" => messages} = history(reader_conn, thread.id)
        assert Enum.map(messages, & &1["body"]) == ["bom dia", "bom dia!"]

        assert Enum.map(messages, & &1["sender"]["id"]) == [ana.id, carlos.id]
      end

      third =
        get(authenticate(json_conn(), outsider), ~p"/api/conversations/#{thread.id}/messages")

      body = json_response(third, 404)
      assert body["errors"]["code"] == "not_found"
      refute Map.has_key?(body, "messages")
    end

    test "a removed group member is refused on send and bounded on read", %{
      conn: conn,
      ana: ana,
      carlos: carlos,
      outsider: joao
    } do
      group = group_with(ana, [carlos, joao])

      before_removal =
        for sender <- [ana, carlos, joao] do
          {:ok, message} =
            Messages.create_message(sender, group.id, %{body: "antes de #{sender.username}"})

          message.id
        end

      removal =
        delete(conn, ~p"/api/conversations/#{group.id}/members/#{carlos.id}")

      assert response(removal, 204)

      assert Messages.create_message(carlos, group.id, %{body: "e agora"}) ==
               {:error, :not_found}

      after_removal =
        for i <- 1..3 do
          {:ok, message} = Messages.create_message(ana, group.id, %{body: "depois #{i}"})
          message.id
        end

      carlos_conn = authenticate(json_conn(), carlos)
      assert %{"messages" => messages, "has_more" => false} = history(carlos_conn, group.id)

      assert Enum.map(messages, & &1["id"]) == before_removal
      assert Enum.all?(after_removal, &(&1 not in Enum.map(messages, fn m -> m["id"] end)))

      # The active members still see the whole thread.
      assert %{"messages" => full} = history(conn, group.id)
      assert length(full) == length(before_removal) + length(after_removal)

      assert {:ok, {:until, %DateTime{}}} = Conversations.read_access(group, carlos)
    end
  end

  # Follows `next_cursor` to exhaustion, returning every id in chronological
  # order alongside the final page.
  defp walk(conn, thread, cursor, acc) do
    params = if cursor, do: %{"before" => cursor}, else: %{}
    page = history(conn, thread.id, params)
    acc = Enum.map(page["messages"], & &1["id"]) ++ acc

    if page["has_more"], do: walk(conn, thread, page["next_cursor"], acc), else: {acc, page}
  end
end
