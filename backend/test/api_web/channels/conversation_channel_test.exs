defmodule ApiWeb.ConversationChannelTest do
  # Channel processes read the database from their own process, so the shared
  # sandbox connection non-async setup provides is required.
  use ApiWeb.ChannelCase, async: false

  import Ecto.Query, only: [from: 2]
  import Plug.Conn, only: [put_req_header: 3]
  import Phoenix.ConnTest, only: [build_conn: 0, delete: 2, get: 2, json_response: 2]

  alias Api.Accounts.Guardian
  alias Api.Conversations
  alias Api.Messages.Message
  alias Api.Repo
  alias ApiWeb.ConversationChannel
  alias Phoenix.Socket.Broadcast

  # --- Setup helpers ------------------------------------------------------

  defp private_pair do
    ana = insert(:user, username: "anabeatriz", name: "Ana Beatriz")
    carlos = insert(:user, username: "carlosedu", name: "Carlos Eduardo")
    {ana, carlos, private_conversation(ana, carlos)}
  end

  defp group_with(creator, members) do
    Enum.each(members, &insert(:contact, owner: creator, user: &1))
    {:ok, group} = Conversations.create_group(creator, "Time", Enum.map(members, & &1.id))
    group
  end

  defp try_join(user, conversation) do
    subscribe_and_join(
      connect_socket(user),
      ConversationChannel,
      "conversation:#{conversation.id}"
    )
  end

  defp joined(user, conversation) do
    {:ok, _reply, socket} = try_join(user, conversation)
    socket
  end

  defp count_messages(conversation_id) do
    Repo.aggregate(from(m in Message, where: m.conversation_id == ^conversation_id), :count)
  end

  defp bearer(user) do
    {:ok, token, _expires_at} = Guardian.issue_token(user)
    put_req_header(build_conn(), "authorization", "Bearer #{token}")
  end

  # --- Join authorization -------------------------------------------------

  test "joins as an active participant, both sides of a private conversation" do
    {ana, carlos, thread} = private_pair()

    assert {:ok, _reply, %Phoenix.Socket{}} = try_join(ana, thread)
    assert {:ok, _reply, %Phoenix.Socket{}} = try_join(carlos, thread)
  end

  test "joins as an active group member" do
    creator = insert(:user, username: "creator")
    member = insert(:user, username: "member")
    group = group_with(creator, [member])

    assert {:ok, _reply, %Phoenix.Socket{}} = try_join(member, group)
  end

  test "rejects a non-participant" do
    {_ana, _carlos, thread} = private_pair()
    outsider = insert(:user, username: "outsider")

    assert {:error, %{reason: "unauthorized"}} = try_join(outsider, thread)
  end

  test "rejects a departed group member" do
    creator = insert(:user, username: "creator")
    member = insert(:user, username: "member")
    group = group_with(creator, [member])
    :ok = Conversations.remove_member(creator, group.id, member.id)

    assert {:error, %{reason: "unauthorized"}} = try_join(member, group)
  end

  test "rejects an unknown conversation id with the outsider's answer" do
    outsider = insert(:user, username: "outsider")
    unknown = Ecto.UUID.generate()

    assert {:error, %{reason: "unauthorized"}} =
             subscribe_and_join(
               connect_socket(outsider),
               ConversationChannel,
               "conversation:#{unknown}"
             )
  end

  test "rejects a malformed conversation id without raising" do
    outsider = insert(:user, username: "outsider")

    assert {:error, %{reason: "unauthorized"}} =
             subscribe_and_join(
               connect_socket(outsider),
               ConversationChannel,
               "conversation:nope"
             )
  end

  # --- Send path ----------------------------------------------------------

  test "replies with the persisted message" do
    {ana, _carlos, thread} = private_pair()
    socket = joined(ana, thread)

    ref = push(socket, "new_message", %{"body" => "bom dia"})

    assert_reply ref, :ok, %{message: message}
    assert message.id
    assert message.inserted_at
    assert message.body == "bom dia"
    assert message.sender.id == ana.id
    assert message.sender.username == "anabeatriz"
    assert message.sender.name == "Ana Beatriz"
  end

  test "echoes client_ref unchanged on success" do
    {ana, _carlos, thread} = private_pair()
    socket = joined(ana, thread)

    ref = push(socket, "new_message", %{"body" => "oi", "client_ref" => "tmp-1"})

    assert_reply ref, :ok, %{client_ref: "tmp-1"}
  end

  test "echoes client_ref on an error reply" do
    {ana, _carlos, thread} = private_pair()
    socket = joined(ana, thread)

    ref = push(socket, "new_message", %{"body" => "", "client_ref" => "tmp-1"})

    assert_reply ref, :error, %{
      reason: "validation_error",
      client_ref: "tmp-1",
      fields: %{body: [_]}
    }
  end

  test "broadcasts message:new to other participants" do
    {ana, carlos, thread} = private_pair()
    _carlos_socket = joined(carlos, thread)
    ana_socket = joined(ana, thread)

    ref = push(ana_socket, "new_message", %{"body" => "bom dia"})
    assert_reply ref, :ok, %{message: message}

    assert_push "message:new", broadcast
    assert broadcast == message
  end

  test "does not broadcast to the sending socket" do
    {ana, _carlos, thread} = private_pair()
    ana_socket = joined(ana, thread)

    ref = push(ana_socket, "new_message", %{"body" => "bom dia"})
    assert_reply ref, :ok, %{}

    refute_push "message:new", _payload, 50
  end

  test "delivers to a second socket of the same user" do
    {ana, _carlos, thread} = private_pair()
    _first = joined(ana, thread)
    second = joined(ana, thread)

    # The first socket sends; the exclusion is by channel process, so the same
    # user's second device is a plain subscriber and still receives the event.
    ref = push(second, "new_message", %{"body" => "de outro aparelho"})
    assert_reply ref, :ok, %{message: message}

    assert_push "message:new", broadcast
    assert broadcast == message
  end

  test "rejects an empty body without broadcasting or persisting" do
    {ana, carlos, thread} = private_pair()
    _carlos_socket = joined(carlos, thread)
    ana_socket = joined(ana, thread)

    ref = push(ana_socket, "new_message", %{"body" => ""})

    assert_reply ref, :error, %{reason: "validation_error", fields: %{body: [_]}}
    refute_push "message:new", _payload, 50
    assert count_messages(thread.id) == 0
  end

  test "rejects a whitespace-only body" do
    {ana, _carlos, thread} = private_pair()
    socket = joined(ana, thread)

    ref = push(socket, "new_message", %{"body" => "   "})

    assert_reply ref, :error, %{reason: "validation_error", fields: %{body: [_]}}
    assert count_messages(thread.id) == 0
  end

  test "rejects a 4001-character body" do
    {ana, _carlos, thread} = private_pair()
    socket = joined(ana, thread)

    ref = push(socket, "new_message", %{"body" => String.duplicate("a", 4001)})

    assert_reply ref, :error, %{reason: "validation_error", fields: %{body: [_]}}
    assert count_messages(thread.id) == 0
  end

  test "accepts a 4000-character body, persisted verbatim" do
    {ana, _carlos, thread} = private_pair()
    socket = joined(ana, thread)
    body = String.duplicate("a", 4000)

    ref = push(socket, "new_message", %{"body" => body})

    assert_reply ref, :ok, %{message: message}
    assert message.body == body
    assert count_messages(thread.id) == 1
  end

  test "rejects a payload with no body key" do
    {ana, _carlos, thread} = private_pair()
    socket = joined(ana, thread)

    ref = push(socket, "new_message", %{"client_ref" => "x"})

    assert_reply ref, :error, %{reason: "validation_error", fields: %{body: [_]}, client_ref: "x"}
  end

  test "rejects a send from a member removed after joining" do
    creator = insert(:user, username: "creator")
    member = insert(:user, username: "member")
    group = group_with(creator, [member])
    socket = joined(member, group)

    :ok = Conversations.remove_member(creator, group.id, member.id)

    ref = push(socket, "new_message", %{"body" => "ainda estou aqui?"})

    assert_reply ref, :error, %{reason: "unauthorized"}
    assert count_messages(group.id) == 0
  end

  test "answers an unknown inbound event without dying" do
    {ana, _carlos, thread} = private_pair()
    socket = joined(ana, thread)

    ref = push(socket, "typing", %{})
    assert_reply ref, :error, %{reason: "unknown_event"}

    # The channel is still alive: a valid send right after still works.
    ref = push(socket, "new_message", %{"body" => "ok"})
    assert_reply ref, :ok, %{}
  end

  test "rate limits the 21st send in a window" do
    {ana, _carlos, thread} = private_pair()
    socket = joined(ana, thread)

    for i <- 1..20 do
      ref = push(socket, "new_message", %{"body" => "m#{i}"})
      assert_reply ref, :ok, %{}
    end

    ref = push(socket, "new_message", %{"body" => "over"})
    assert_reply ref, :error, %{reason: "rate_limited", retry_after_ms: ms}
    assert ms in 1..10_000

    assert count_messages(thread.id) == 20

    # The connection stays usable: a later join still succeeds.
    assert {:ok, _reply, _socket} = try_join(ana, thread)
  end

  # --- Fan-out ------------------------------------------------------------

  test "pushes conversation:updated to every participant, sender's copy read" do
    creator = insert(:user, username: "creator", name: "Creator")
    m1 = insert(:user, username: "m1")
    m2 = insert(:user, username: "m2")
    group = group_with(creator, [m1, m2])

    for id <- [creator.id, m1.id, m2.id] do
      Phoenix.PubSub.subscribe(Api.PubSub, "user:#{id}")
    end

    socket = joined(creator, group)
    push(socket, "new_message", %{"body" => "novidades"})

    assert_receive %Broadcast{
      topic: "user:" <> _,
      event: "conversation:updated",
      payload: creator_payload
    }

    assert creator_payload.conversation_id == group.id
    assert creator_payload.last_message.sender_id == creator.id

    # Each of the three personal topics receives it; the sender's is read.
    unreads =
      for _ <- 1..2 do
        assert_receive %Broadcast{event: "conversation:updated", payload: p}
        p.unread
      end

    assert creator_payload.unread == false
    assert Enum.sort([creator_payload.unread | unreads]) == [false, true, true]
  end

  test "truncates the preview at 120 characters, leaving the message body whole" do
    {ana, carlos, thread} = private_pair()
    Phoenix.PubSub.subscribe(Api.PubSub, "user:#{carlos.id}")
    body = String.duplicate("a", 200)

    socket = joined(ana, thread)
    ref = push(socket, "new_message", %{"body" => body})

    assert_reply ref, :ok, %{message: message}
    assert message.body == body

    assert_receive %Broadcast{event: "conversation:updated", payload: payload}
    assert String.length(payload.last_message.preview) == 120
    assert payload.last_message.preview == String.slice(body, 0, 120)
  end

  test "handles 5 concurrent senders of 20 messages each" do
    creator = insert(:user, username: "creator")
    senders_users = for i <- 1..5, do: insert(:user, username: "sender#{i}")
    group = group_with(creator, senders_users)

    # The sockets must connect from the test process, so they are joined with
    # plain `join` rather than `subscribe_and_join`: only the latter subscribes
    # the test process to the topic, and five such joins would each deliver
    # every broadcast to the test process and inflate the count. The test
    # process instead subscribes exactly once, standing in for a sixth
    # subscriber the sender exclusion never touches.
    sender_sockets =
      Enum.map(senders_users, fn user ->
        {:ok, _reply, socket} =
          join(connect_socket(user), ConversationChannel, "conversation:#{group.id}")

        socket
      end)

    Phoenix.PubSub.subscribe(Api.PubSub, "conversation:#{group.id}")

    sender_sockets
    |> Enum.map(fn socket ->
      Task.async(fn ->
        for i <- 1..20, do: push(socket, "new_message", %{"body" => "m#{i}"})
      end)
    end)
    |> Enum.each(&Task.await(&1, 15_000))

    # Flush every channel's mailbox so all 100 inserts have committed.
    Enum.each(sender_sockets, &:sys.get_state(&1.channel_pid))

    assert count_messages(group.id) == 100

    ids =
      for _ <- 1..100 do
        assert_receive %Broadcast{event: "message:new", payload: payload}, 2000
        payload.id
      end

    assert length(Enum.uniq(ids)) == 100
    refute_receive %Broadcast{event: "message:new"}, 50
  end

  # --- Membership revocation ----------------------------------------------

  test "pushes membership_revoked to the removed member only, then stops it" do
    creator = insert(:user, username: "creator")
    m1 = insert(:user, username: "m1")
    m2 = insert(:user, username: "m2")
    group = group_with(creator, [m1, m2])

    {:ok, _reply, m1_socket} = try_join(m1, group)
    {:ok, _reply, m2_socket} = try_join(m2, group)
    m1_ref = Process.monitor(m1_socket.channel_pid)
    m2_ref = Process.monitor(m2_socket.channel_pid)

    conn = delete(bearer(creator), "/api/conversations/#{group.id}/members/#{m1.id}")
    assert conn.status == 204

    assert_push "conversation:membership_revoked", %{conversation_id: conversation_id}
    assert conversation_id == group.id
    assert_receive {:DOWN, ^m1_ref, :process, _pid, :normal}

    # m2's channel neither pushed nor stopped.
    refute_push "conversation:membership_revoked", _payload, 50
    refute_receive {:DOWN, ^m2_ref, :process, _pid, _reason}, 50
  end

  test "rejects a rejoin after revocation" do
    creator = insert(:user, username: "creator")
    member = insert(:user, username: "member")
    group = group_with(creator, [member])
    {:ok, _reply, _socket} = try_join(member, group)

    conn = delete(bearer(creator), "/api/conversations/#{group.id}/members/#{member.id}")
    assert conn.status == 204

    assert {:error, %{reason: "unauthorized"}} = try_join(member, group)
  end

  test "does not revoke on a voluntary leave" do
    creator = insert(:user, username: "creator")
    member = insert(:user, username: "member")
    group = group_with(creator, [member])
    {:ok, _reply, _socket} = try_join(member, group)

    conn = delete(bearer(member), "/api/conversations/#{group.id}/members/me")
    assert conn.status == 204

    refute_push "conversation:membership_revoked", _payload, 50
    assert {:error, %{reason: "unauthorized"}} = try_join(member, group)
  end

  # --- Cross-feature integration -----------------------------------------

  test "a broadcast message is the exact record the history endpoint returns" do
    {ana, carlos, thread} = private_pair()
    ana_socket = joined(ana, thread)

    ref = push(ana_socket, "new_message", %{"body" => "bom dia, time"})
    assert_reply ref, :ok, %{message: sent}

    conn = get(bearer(carlos), "/api/conversations/#{thread.id}/messages")
    assert %{"messages" => [history]} = json_response(conn, 200)

    assert history["id"] == sent.id
    assert history["conversation_id"] == sent.conversation_id
    assert history["body"] == sent.body
    assert history["sender"]["id"] == sent.sender.id
    assert history["sender"]["username"] == sent.sender.username
    assert history["inserted_at"] == DateTime.to_iso8601(sent.inserted_at)
  end

  test "a socket connection is the lifecycle presence will consume" do
    {ana, _carlos, thread} = private_pair()
    socket = connect_socket(ana)

    assert ApiWeb.UserSocket.id(socket) == "user_socket:#{ana.id}"

    {:ok, _reply, joined_socket} =
      subscribe_and_join(socket, ConversationChannel, "conversation:#{thread.id}")

    # The channel is linked to the test process on join; unlink before closing
    # so its shutdown does not take the test down with it.
    Process.unlink(joined_socket.channel_pid)
    ref = Process.monitor(joined_socket.channel_pid)
    close(joined_socket)

    assert_receive {:DOWN, ^ref, :process, _pid, _reason}
  end
end
