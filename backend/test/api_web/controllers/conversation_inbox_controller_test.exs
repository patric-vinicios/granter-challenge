defmodule ApiWeb.ConversationInboxControllerTest do
  use ApiWeb.ConnCase, async: true

  import Ecto.Query

  alias Api.Accounts.Guardian
  alias Api.Conversations.Participant
  alias Api.Repo

  setup do
    caller = insert(:user, username: "primary", name: "Primary User")
    {:ok, conn: authenticate(json_conn(), caller), caller: caller}
  end

  describe "GET /api/conversations" do
    test "returns every active conversation in one response", %{conn: conn, caller: caller} do
      private = private_pair(caller, insert(:user))
      group = group_with(caller, name: "Time")

      %{"conversations" => conversations} =
        conn |> get(~p"/api/conversations") |> json_response(200)

      ids = Enum.map(conversations, & &1["id"])
      assert private.id in ids
      assert group.id in ids

      entry = Enum.find(conversations, &(&1["id"] == group.id))

      assert Map.keys(entry) |> Enum.sort() ==
               ~w(counterpart id last_message last_read_at member_count title type unread_count unread_overflow)
    end

    test "orders by last activity with message-less conversations last", %{
      conn: conn,
      caller: caller
    } do
      newer = messaged_pair(caller, ago(10))
      older = messaged_pair(caller, ago(100))
      empty = private_pair(caller, insert(:user), joined_at: ago(5))

      %{"conversations" => conversations} =
        conn |> get(~p"/api/conversations") |> json_response(200)

      assert Enum.map(conversations, & &1["id"]) == [newer.id, older.id, empty.id]
    end

    test "carries the counterpart display name as the title for private", %{
      conn: conn,
      caller: caller
    } do
      other = insert(:user, name: "Ana Beatriz")
      private_pair(caller, other)

      [entry] =
        conn |> get(~p"/api/conversations") |> json_response(200) |> Map.fetch!("conversations")

      assert entry["title"] == "Ana Beatriz"
      assert entry["counterpart"]["id"] == other.id
      assert entry["counterpart"]["username"] == other.username
      assert entry["member_count"] == nil
    end

    test "carries the group name and active member count for groups", %{
      conn: conn,
      caller: caller
    } do
      group = group_with(caller, name: "Família")
      seat(group, insert(:user))
      removed = insert(:user)
      seat(group, removed, left_at: ago(5))

      [entry] =
        conn |> get(~p"/api/conversations") |> json_response(200) |> Map.fetch!("conversations")

      assert entry["title"] == "Família"
      assert entry["member_count"] == 2
    end

    test "truncates the preview to at most 120 characters", %{conn: conn, caller: caller} do
      other = insert(:user)
      conv = private_pair(caller, other)
      body = String.duplicate("palavra ", 60) |> String.trim()

      message =
        insert(:message, conversation: conv, sender: other, body: body, inserted_at: ago(10))

      [entry] =
        conn |> get(~p"/api/conversations") |> json_response(200) |> Map.fetch!("conversations")

      preview = entry["last_message"]["body"]
      assert String.length(preview) <= 120
      assert String.ends_with?(preview, "…")

      %{"messages" => [history]} =
        conn |> get(~p"/api/conversations/#{conv.id}/messages") |> json_response(200)

      assert history["id"] == message.id
      assert history["body"] == body
      assert preview != body
    end

    test "carries the last message sender id and timestamp", %{conn: conn, caller: caller} do
      other = insert(:user)
      conv = private_pair(caller, other)
      message = insert(:message, conversation: conv, sender: other, inserted_at: ago(10))

      [entry] =
        conn |> get(~p"/api/conversations") |> json_response(200) |> Map.fetch!("conversations")

      assert entry["last_message"]["sender_id"] == other.id
      assert entry["last_message"]["inserted_at"] == DateTime.to_iso8601(message.inserted_at)
    end

    test "executes the same number of queries with 5 and with 50 conversations", %{caller: caller} do
      for _ <- 1..5, do: messaged_pair(caller, ago(10))
      conn = authenticate(json_conn(), caller)
      small = count_queries(fn -> get(conn, ~p"/api/conversations") end)

      other = insert(:user, username: "heavy")
      for _ <- 1..50, do: messaged_pair(other, ago(10))
      other_conn = authenticate(json_conn(), other)
      large = count_queries(fn -> get(other_conn, ~p"/api/conversations") end)

      assert small == large
      assert small <= 3
    end

    test "excludes the caller's own messages from the badge", %{conn: conn, caller: caller} do
      other = insert(:user)
      conv = private_pair(caller, other)
      insert(:message, conversation: conv, sender: caller, inserted_at: ago(10))

      [entry] =
        conn |> get(~p"/api/conversations") |> json_response(200) |> Map.fetch!("conversations")

      assert entry["unread_count"] == 0
    end

    test "reports 99 with unread_overflow for more than 99 unread", %{conn: conn, caller: caller} do
      other = insert(:user)
      conv = private_pair(caller, other)
      seed_unread(conv, other, 120)

      [entry] =
        conn |> get(~p"/api/conversations") |> json_response(200) |> Map.fetch!("conversations")

      assert entry["unread_count"] == 99
      assert entry["unread_overflow"] == true
    end

    test "returns an empty array for a caller with no conversations", %{conn: conn} do
      assert %{"conversations" => []} = conn |> get(~p"/api/conversations") |> json_response(200)
    end
  end

  describe "GET /api/conversations?q=" do
    test "returns only conversations whose title matches", %{conn: conn, caller: caller} do
      private_pair(caller, insert(:user, name: "Ana Beatriz"))
      private_pair(caller, insert(:user, name: "Bruno Carvalho"))

      titles = titles_for(conn, "ana")

      assert titles == ["Ana Beatriz"]
    end

    test "matches group names and private @usernames and display names", %{
      conn: conn,
      caller: caller
    } do
      group_with(caller, name: "Marketing")
      private_pair(caller, insert(:user, username: "carlosx", name: "Zeta Silva"))
      private_pair(caller, insert(:user, name: "Diana Prince"))

      assert titles_for(conn, "marketing") == ["Marketing"]
      assert titles_for(conn, "carlosx") == ["Zeta Silva"]
      assert titles_for(conn, "diana") == ["Diana Prince"]
    end

    test "is accent- and case-insensitive", %{conn: conn, caller: caller} do
      group_with(caller, name: "Família")

      assert titles_for(conn, "familia") == ["Família"]
      assert titles_for(conn, "FAMÍLIA") == ["Família"]
    end

    test "returns the full list for a blank q", %{conn: conn, caller: caller} do
      private_pair(caller, insert(:user, name: "Ana Beatriz"))
      group_with(caller, name: "Marketing")

      assert length(titles_for(conn, "")) == 2
    end
  end

  describe "POST /api/conversations/:id/read" do
    test "clears the badge and keeps it cleared on the next list", %{conn: conn, caller: caller} do
      other = insert(:user)
      conv = private_pair(caller, other)
      for _ <- 1..3, do: insert(:message, conversation: conv, sender: other, inserted_at: ago(10))

      body = conn |> post(~p"/api/conversations/#{conv.id}/read") |> json_response(200)
      assert body["conversation_id"] == conv.id
      assert body["unread_count"] == 0
      assert body["last_read_at"]

      [entry] =
        conn |> get(~p"/api/conversations") |> json_response(200) |> Map.fetch!("conversations")

      assert entry["unread_count"] == 0
    end

    test "is idempotent across two calls", %{conn: conn, caller: caller} do
      conv = private_pair(caller, insert(:user))

      first = conn |> post(~p"/api/conversations/#{conv.id}/read") |> json_response(200)
      second = conn |> post(~p"/api/conversations/#{conv.id}/read") |> json_response(200)

      {:ok, t1, 0} = DateTime.from_iso8601(first["last_read_at"])
      {:ok, t2, 0} = DateTime.from_iso8601(second["last_read_at"])
      assert DateTime.compare(t2, t1) != :lt
    end

    test "returns 404 marking a conversation the caller does not participate in", %{conn: conn} do
      strangers = private_pair(insert(:user), insert(:user))

      body = conn |> post(~p"/api/conversations/#{strangers.id}/read") |> json_response(404)
      assert body["errors"]["code"] == "not_found"
      refute Map.has_key?(body, "conversation_id")
    end

    test "returns 403 marking a conversation the caller has left", %{conn: conn, caller: caller} do
      group = group_with(caller)
      seat(group, insert(:user))

      Repo.update_all(
        from(p in Participant, where: p.conversation_id == ^group.id and p.user_id == ^caller.id),
        set: [left_at: ago(5)]
      )

      body = conn |> post(~p"/api/conversations/#{group.id}/read") |> json_response(403)
      assert body["errors"]["code"] == "not_a_participant"
    end

    test "returns 400 for a non-UUID conversation id", %{conn: conn} do
      body = conn |> post(~p"/api/conversations/nope/read") |> json_response(400)
      assert body["errors"]["code"] == "invalid_id"
    end
  end

  test "both endpoints require authentication" do
    conv = private_pair(insert(:user), insert(:user))
    anon = json_conn()

    assert anon |> get(~p"/api/conversations") |> json_response(401) |> get_in(["errors", "code"]) ==
             "unauthenticated"

    assert anon
           |> post(~p"/api/conversations/#{conv.id}/read")
           |> json_response(401)
           |> get_in(["errors", "code"]) == "unauthenticated"
  end

  describe "cross-feature integration" do
    test "private conversations appear with the counterpart as the title", %{
      conn: conn,
      caller: caller
    } do
      other = insert(:user, name: "Carlos Eduardo")
      insert(:contact, owner: caller, user: other)

      created =
        conn
        |> post(~p"/api/conversations/private", %{"user_id" => other.id})
        |> json_response(201)
        |> get_in(["conversation", "id"])

      [entry] =
        conn |> get(~p"/api/conversations") |> json_response(200) |> Map.fetch!("conversations")

      assert entry["id"] == created
      assert entry["title"] == "Carlos Eduardo"
      assert entry["counterpart"]["id"] == other.id
    end

    test "groups appear with their name and member count, and disappear once the caller leaves",
         %{
           conn: conn,
           caller: caller
         } do
      m1 = insert(:user)
      m2 = insert(:user)
      insert(:contact, owner: caller, user: m1)
      insert(:contact, owner: caller, user: m2)

      group =
        conn
        |> post(~p"/api/conversations/groups", %{
          "name" => "Time de Produto",
          "member_ids" => [m1.id, m2.id]
        })
        |> json_response(201)
        |> get_in(["conversation", "id"])

      [entry] =
        conn |> get(~p"/api/conversations") |> json_response(200) |> Map.fetch!("conversations")

      assert entry["id"] == group
      assert entry["title"] == "Time de Produto"
      assert entry["member_count"] == 3

      assert conn |> delete(~p"/api/conversations/#{group}/members/me") |> response(204)

      ids =
        conn
        |> get(~p"/api/conversations")
        |> json_response(200)
        |> Map.fetch!("conversations")
        |> Enum.map(& &1["id"])

      refute group in ids
    end

    test "the last persisted message is previewed and moves its conversation to the top", %{
      conn: conn,
      caller: caller
    } do
      quiet = private_pair(caller, insert(:user))
      insert(:message, conversation: quiet, sender: insert(:user), inserted_at: ago(500))

      other = insert(:user)
      active = private_pair(caller, other)

      newest =
        insert(:message, conversation: active, sender: other, body: "latest", inserted_at: ago(1))

      %{"conversations" => [first | _]} =
        conn |> get(~p"/api/conversations") |> json_response(200)

      assert first["id"] == active.id
      assert first["last_message"]["id"] == newest.id
      assert first["last_message"]["sender_id"] == other.id
      assert first["last_message"]["inserted_at"] == DateTime.to_iso8601(newest.inserted_at)
    end

    test "the filtered list returns the exact unfiltered summary entry shape", %{
      conn: conn,
      caller: caller
    } do
      other = insert(:user, name: "Ana Beatriz")
      conv = private_pair(caller, other)
      insert(:message, conversation: conv, sender: other, body: "oi", inserted_at: ago(10))

      unfiltered =
        conn
        |> get(~p"/api/conversations")
        |> json_response(200)
        |> Map.fetch!("conversations")
        |> Enum.find(&(&1["id"] == conv.id))

      filtered =
        conn
        |> get(~p"/api/conversations?q=ana")
        |> json_response(200)
        |> Map.fetch!("conversations")
        |> Enum.find(&(&1["id"] == conv.id))

      assert filtered == unfiltered
    end
  end

  defp titles_for(conn, q) do
    conn
    |> get(~p"/api/conversations?q=#{q}")
    |> json_response(200)
    |> Map.fetch!("conversations")
    |> Enum.map(& &1["title"])
  end

  defp ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)

  defp pair_key(a, b), do: Enum.join(Enum.sort([a.id, b.id]), ":")

  defp seat(conversation, user, attrs \\ []) do
    insert(:participant, [conversation: conversation, user: user, joined_at: ago(3600)] ++ attrs)
  end

  defp private_pair(caller, other, opts \\ []) do
    conv = insert(:conversation, participant_key: pair_key(caller, other))

    seat(conv, caller,
      joined_at: opts[:joined_at] || ago(3600),
      last_read_at: opts[:last_read_at]
    )

    seat(conv, other)
    conv
  end

  defp group_with(caller, opts \\ []) do
    group =
      insert(:conversation,
        type: :group,
        name: opts[:name] || "Grupo #{System.unique_integer([:positive])}",
        creator: caller
      )

    seat(group, caller, joined_at: opts[:joined_at] || ago(3600))
    group
  end

  defp messaged_pair(caller, last_at) do
    other = insert(:user)
    conv = private_pair(caller, other)
    insert(:message, conversation: conv, sender: other, inserted_at: last_at)
    conv
  end

  defp seed_unread(conversation, sender, count) do
    entries =
      for n <- 1..count do
        now = ago(count - n)

        %{
          id: Ecto.UUID.generate(),
          conversation_id: conversation.id,
          sender_id: sender.id,
          body: "unread #{n}",
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(Api.Messages.Message, entries)
  end

  defp authenticate(conn, user) do
    {:ok, token, _expires_at} = Guardian.issue_token(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
