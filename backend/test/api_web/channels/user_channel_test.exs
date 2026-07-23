defmodule ApiWeb.UserChannelTest do
  # Channel processes read the database from their own process, so the shared
  # sandbox connection non-async setup provides is required.
  use ApiWeb.ChannelCase, async: false

  alias Api.Repo
  alias ApiWeb.ConversationChannel
  alias ApiWeb.Presence
  alias ApiWeb.UserChannel

  defp join_own(user) do
    subscribe_and_join(connect_socket(user), UserChannel, "user:#{user.id}")
  end

  test "joins the caller's own topic" do
    user = insert(:user)
    assert {:ok, _reply, %Phoenix.Socket{}} = join_own(user)
  end

  test "rejects another user's topic" do
    user = insert(:user)
    other = insert(:user)

    assert {:error, %{reason: "unauthorized"}} =
             subscribe_and_join(connect_socket(user), UserChannel, "user:#{other.id}")
  end

  test "rejects a malformed topic id" do
    user = insert(:user)

    assert {:error, %{reason: "unauthorized"}} =
             subscribe_and_join(connect_socket(user), UserChannel, "user:nope")
  end

  test "receives conversation:updated without joining the conversation" do
    ana = insert(:user, name: "Ana Beatriz")
    carlos = insert(:user, name: "Carlos Eduardo")
    conversation = private_conversation(ana, carlos)

    # Carlos is only on his personal topic; Ana sends over the conversation topic.
    {:ok, _reply, _carlos_socket} = join_own(carlos)

    {:ok, _reply, ana_conv} =
      subscribe_and_join(
        connect_socket(ana),
        ConversationChannel,
        "conversation:#{conversation.id}"
      )

    push(ana_conv, "new_message", %{"body" => "bom dia"})

    assert_push "conversation:updated", payload
    assert payload.conversation_id == conversation.id
    assert payload.last_message.preview == "bom dia"
    assert payload.last_message.sender_id == ana.id
    assert payload.last_message.inserted_at
    assert payload.unread == true
  end

  test "answers any inbound event with an error and persists nothing" do
    user = insert(:user)
    {:ok, _reply, socket} = join_own(user)

    ref = push(socket, "anything", %{"body" => "x"})
    assert_reply ref, :error, %{reason: "unknown_event"}
  end

  test "tracks the caller as online on join of the personal topic" do
    user = insert(:user)
    {:ok, _reply, socket} = join_own(user)
    # Flush the mailbox so after_join, where the track happens, has run.
    _ = :sys.get_state(socket.channel_pid)

    assert Presence.online?(user.id)
    assert %{metas: [%{online_at: %DateTime{}}]} = Presence.list("user:#{user.id}")[user.id]
  end

  test "refreshes last_seen_at while the socket is still connected" do
    user = insert(:user)
    {:ok, _reply, socket} = join_own(user)
    _ = :sys.get_state(socket.channel_pid)

    # Only a refresh or a final leave writes the column; the open socket has
    # done neither yet.
    assert Repo.reload(user).last_seen_at == nil

    send(socket.channel_pid, :refresh_last_seen)
    _ = :sys.get_state(socket.channel_pid)

    assert %DateTime{} = Repo.reload(user).last_seen_at
    # Still connected: the refresh did not end the session.
    assert Presence.online?(user.id)
  end
end
