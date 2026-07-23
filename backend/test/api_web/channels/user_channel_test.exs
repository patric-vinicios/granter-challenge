defmodule ApiWeb.UserChannelTest do
  # Channel processes read the database from their own process, so the shared
  # sandbox connection non-async setup provides is required.
  use ApiWeb.ChannelCase, async: false

  alias ApiWeb.ConversationChannel
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
end
