defmodule Api.ConversationsTest do
  use Api.DataCase, async: true

  alias Api.Contacts
  alias Api.Contacts.Contact
  alias Api.Conversations
  alias Api.Conversations.Conversation
  alias Api.Conversations.Participant

  describe "create_private_conversation/2" do
    setup do
      caller = insert(:user, username: "anabeatriz", name: "Ana Beatriz")
      target = insert(:user, username: "carlos", name: "Carlos Silva")
      insert(:contact, owner: caller, user: target)

      %{caller: caller, target: target}
    end

    test "creates a conversation and two participants", %{caller: caller, target: target} do
      assert {:ok, :created, conversation} =
               Conversations.create_private_conversation(caller, target.id)

      assert conversation.type == :private
      assert conversation.participant_key == Enum.join(Enum.sort([caller.id, target.id]), ":")
      assert [_, _] = conversation.participants
      assert Enum.all?(conversation.participants, &match?(%{user: %{id: _}}, &1))
      assert Repo.aggregate(Conversation, :count) == 1
      assert Repo.aggregate(Participant, :count) == 2
    end

    test "returns the existing conversation on a second call", %{caller: caller, target: target} do
      assert {:ok, :created, first} = Conversations.create_private_conversation(caller, target.id)

      assert {:ok, :existing, second} =
               Conversations.create_private_conversation(caller, target.id)

      assert second.id == first.id
      assert Repo.aggregate(Conversation, :count) == 1
      assert Repo.aggregate(Participant, :count) == 2
    end

    test "is symmetric across the pair", %{caller: caller, target: target} do
      # The target must have the initiator as a contact to open it from their side.
      insert(:contact, owner: target, user: caller)

      assert {:ok, :created, opened} =
               Conversations.create_private_conversation(caller, target.id)

      assert {:ok, :existing, reopened} =
               Conversations.create_private_conversation(target, caller.id)

      assert reopened.id == opened.id
      assert Repo.aggregate(Conversation, :count) == 1
    end

    test "rejects a non-contact", %{caller: caller} do
      stranger = insert(:user)

      assert {:error, :not_a_contact} =
               Conversations.create_private_conversation(caller, stranger.id)

      assert Repo.aggregate(Conversation, :count) == 0
      assert Repo.aggregate(Participant, :count) == 0
    end

    test "rejects self before the contact rule", %{caller: caller} do
      assert {:error, :self_conversation} =
               Conversations.create_private_conversation(caller, caller.id)

      assert Repo.aggregate(Conversation, :count) == 0
    end

    test "returns :user_not_found for an unknown or non-UUID id", %{caller: caller} do
      for id <- [Ecto.UUID.generate(), "not-a-uuid"] do
        assert {:error, :user_not_found} =
                 Conversations.create_private_conversation(caller, id)
      end

      assert Repo.aggregate(Conversation, :count) == 0
    end

    test "a concurrent duplicate raced past the pre-check is a caught error", %{
      caller: caller,
      target: target
    } do
      key = Enum.join(Enum.sort([caller.id, target.id]), ":")

      assert {:ok, _} = %Conversation{} |> Conversation.private_changeset(key) |> Repo.insert()

      assert {:error, %Ecto.Changeset{}} =
               %Conversation{} |> Conversation.private_changeset(key) |> Repo.insert()
    end

    test "creation is transactional", %{caller: caller, target: target} do
      # Replicate the context's multi but force the second participant insert to
      # collide on (conversation_id, user_id), so the whole write must roll back.
      key = Enum.join(Enum.sort([caller.id, target.id]), ":")
      now = DateTime.utc_now()

      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:conversation, Conversation.private_changeset(%Conversation{}, key))
        |> Ecto.Multi.insert(:first, &member(&1.conversation, caller, now))
        |> Ecto.Multi.insert(:second, &member(&1.conversation, caller, now))

      assert {:error, :second, %Ecto.Changeset{}, _} = Repo.transaction(multi)
      assert Repo.aggregate(Conversation, :count) == 0
      assert Repo.aggregate(Participant, :count) == 0
    end

    test "returns :not_a_contact after the contact is removed", %{
      caller: caller,
      target: target
    } do
      assert {:ok, :created, _} = Conversations.create_private_conversation(caller, target.id)

      pair = Repo.get_by!(Contact, owner_id: caller.id, contact_user_id: target.id)
      Repo.delete!(pair)

      assert {:error, :not_a_contact} =
               Conversations.create_private_conversation(caller, target.id)

      assert Repo.aggregate(Conversation, :count) == 1
    end
  end

  describe "get_conversation/2" do
    setup do
      caller = insert(:user)
      target = insert(:user)
      insert(:contact, owner: caller, user: target)
      {:ok, :created, conversation} = Conversations.create_private_conversation(caller, target.id)

      %{caller: caller, target: target, conversation: conversation}
    end

    test "returns the conversation with both participants for a participant", %{
      caller: caller,
      target: target,
      conversation: conversation
    } do
      assert {:ok, read} = Conversations.get_conversation(caller, conversation.id)

      assert read.id == conversation.id

      participant_ids = Enum.map(read.participants, & &1.user_id)
      assert Enum.sort(participant_ids) == Enum.sort([caller.id, target.id])
      assert Enum.all?(read.participants, &match?(%{user: %{id: _}}, &1))
    end

    test "the target participates without adding the initiator back", %{
      caller: caller,
      target: target,
      conversation: conversation
    } do
      refute Contacts.contact?(target, caller)
      assert Conversations.participant?(conversation, target)
      assert {:ok, _} = Conversations.get_conversation(target, conversation.id)
    end

    test "returns :not_found for a non-participant", %{conversation: conversation} do
      outsider = insert(:user)

      assert {:error, :not_found} = Conversations.get_conversation(outsider, conversation.id)
    end

    test "returns :not_found for a well-formed but unknown id", %{caller: caller} do
      assert {:error, :not_found} =
               Conversations.get_conversation(caller, Ecto.UUID.generate())
    end

    test "returns :invalid_id for a non-UUID id", %{caller: caller} do
      for id <- ["not-a-uuid", ""] do
        assert {:error, :invalid_id} = Conversations.get_conversation(caller, id)
      end
    end

    test "still returns after the initiator removes the contact", %{
      caller: caller,
      target: target,
      conversation: conversation
    } do
      pair = Repo.get_by!(Api.Contacts.Contact, owner_id: caller.id, contact_user_id: target.id)
      Repo.delete!(pair)

      assert {:ok, read} = Conversations.get_conversation(caller, conversation.id)
      assert read.id == conversation.id
    end
  end

  describe "participant?/2" do
    test "is true only for an active member" do
      caller = insert(:user)
      target = insert(:user)
      conversation = private_conversation(caller, target)
      outsider = insert(:user)

      departed = insert(:user)

      insert(:participant,
        conversation: conversation,
        user: departed,
        left_at: DateTime.utc_now()
      )

      assert Conversations.participant?(conversation, caller)
      assert Conversations.participant?(conversation.id, target.id)
      refute Conversations.participant?(conversation, outsider)
      refute Conversations.participant?(conversation, departed)
    end
  end

  defp member(conversation, user, joined_at) do
    %Participant{conversation_id: conversation.id, user_id: user.id}
    |> Participant.changeset(%{joined_at: joined_at})
  end
end
