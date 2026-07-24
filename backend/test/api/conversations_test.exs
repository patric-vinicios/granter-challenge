defmodule Api.ConversationsTest do
  use Api.DataCase, async: true

  import Ecto.Query

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

  describe "read_access/2" do
    setup do
      caller = insert(:user)
      target = insert(:user)

      %{caller: caller, target: target, conversation: private_conversation(caller, target)}
    end

    test "returns active for a current participant", %{caller: caller, conversation: thread} do
      assert Conversations.read_access(thread, caller) == {:ok, :active}
      assert Conversations.read_access(thread.id, caller.id) == {:ok, :active}
    end

    test "returns the bound for a departed member", %{conversation: thread} do
      left_at = DateTime.utc_now()
      departed = insert(:user)
      insert(:participant, conversation: thread, user: departed, left_at: left_at)

      assert {:ok, {:until, ^left_at}} = Conversations.read_access(thread, departed)
    end

    test "returns not_found for an outsider", %{conversation: thread} do
      assert Conversations.read_access(thread, insert(:user)) == {:error, :not_found}
    end

    test "returns not_found for an unknown conversation", %{caller: caller} do
      assert Conversations.read_access(Ecto.UUID.generate(), caller) == {:error, :not_found}
    end

    test "rejects a malformed id", %{caller: caller, conversation: thread} do
      assert Conversations.read_access("nope", caller) == {:error, :invalid_id}
      assert Conversations.read_access(thread.id, "nope") == {:error, :invalid_id}
    end

    test "returns active again after a re-add" do
      {creator, [contact]} = creator_with_contacts(1)
      {:ok, group} = Conversations.create_group(creator, "Time", [contact.id])

      assert :ok = Conversations.remove_member(creator, group.id, contact.id)
      assert {:ok, {:until, %DateTime{}}} = Conversations.read_access(group, contact)
      # The predicate keeps its own answer: a departed member may read, not write.
      refute Conversations.participant?(group, contact)

      assert {:ok, _} = Conversations.add_members(creator, group.id, [contact.id])
      assert Conversations.read_access(group, contact) == {:ok, :active}
      assert Conversations.participant?(group, contact)
    end
  end

  # A creator with a number of contacts, the common starting point for a group.
  defp creator_with_contacts(count \\ 2) do
    creator = insert(:user, username: "creator", name: "Creator")

    contacts =
      for i <- 1..count do
        contact = insert(:user, username: "contact#{i}", name: "Contact #{i}")
        insert(:contact, owner: creator, user: contact)
        contact
      end

    {creator, contacts}
  end

  defp active_ids(conversation_id) do
    Participant
    |> where([p], p.conversation_id == ^conversation_id and is_nil(p.left_at))
    |> select([p], p.user_id)
    |> Repo.all()
    |> MapSet.new()
  end

  describe "create_group/3" do
    test "seats the creator and the members in one transaction" do
      {creator, [c1, c2]} = creator_with_contacts()

      assert {:ok, %Conversation{} = group} =
               Conversations.create_group(creator, "Time", [c1.id, c2.id])

      assert group.type == :group
      assert MapSet.equal?(active_ids(group.id), MapSet.new([creator.id, c1.id, c2.id]))
      assert match?([_, _, _], group.participants)
    end

    test "adds the creator automatically without them in member_ids" do
      {creator, [c1, _c2]} = creator_with_contacts()

      assert {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])
      assert creator.id in MapSet.to_list(active_ids(group.id))
    end

    test "strips the creator's own id from member_ids" do
      {creator, [c1, _c2]} = creator_with_contacts()

      assert {:ok, group} = Conversations.create_group(creator, "Time", [creator.id, c1.id])

      assert MapSet.equal?(active_ids(group.id), MapSet.new([creator.id, c1.id]))

      assert Repo.aggregate(
               from(p in Participant, where: p.user_id == ^creator.id),
               :count
             ) == 1
    end

    test "de-duplicates repeated member_ids" do
      {creator, [c1, _c2]} = creator_with_contacts()

      assert {:ok, group} = Conversations.create_group(creator, "Time", [c1.id, c1.id])

      assert Repo.aggregate(
               from(p in Participant,
                 where: p.conversation_id == ^group.id and p.user_id == ^c1.id
               ),
               :count
             ) == 1
    end

    test "rejects a non-contact and inserts nothing" do
      {creator, [c1, _c2]} = creator_with_contacts()
      stranger = insert(:user, username: "stranger", name: "Stranger")

      assert {:error, :not_a_contact, detail} =
               Conversations.create_group(creator, "Time", [c1.id, stranger.id])

      assert detail =~ "@stranger"
      refute detail =~ "@contact1"
      assert Repo.aggregate(from(c in Conversation, where: c.type == :group), :count) == 0
    end

    test "rejects an empty member set" do
      {creator, _} = creator_with_contacts()

      assert {:error, %Ecto.Changeset{}} = Conversations.create_group(creator, "Time", [])
      assert Repo.aggregate(from(c in Conversation, where: c.type == :group), :count) == 0
    end

    test "rejects a member set that is empty after stripping the creator" do
      {creator, _} = creator_with_contacts()

      assert {:error, %Ecto.Changeset{} = changeset} =
               Conversations.create_group(creator, "Time", [creator.id])

      assert %{member_ids: [_ | _]} = errors_on(changeset)
      assert Repo.aggregate(from(c in Conversation, where: c.type == :group), :count) == 0
    end

    test "rejects a name outside 1..60" do
      {creator, [c1, _c2]} = creator_with_contacts()

      for name <- ["", String.duplicate("a", 61)] do
        assert {:error, %Ecto.Changeset{} = changeset} =
                 Conversations.create_group(creator, name, [c1.id])

        assert %{name: [_ | _]} = errors_on(changeset)
      end

      assert Repo.aggregate(from(c in Conversation, where: c.type == :group), :count) == 0
    end

    test "trims the name before validating it" do
      {creator, [c1, _c2]} = creator_with_contacts()

      assert {:ok, group} = Conversations.create_group(creator, "  Time  ", [c1.id])
      assert group.name == "Time"
    end

    test "rejects a membership over 256" do
      creator = insert(:user, username: "creator")

      ids =
        for i <- 1..256 do
          contact = insert(:user, username: "over#{i}")
          insert(:contact, owner: creator, user: contact)
          contact.id
        end

      assert {:error, %Ecto.Changeset{} = changeset} =
               Conversations.create_group(creator, "Huge", ids)

      assert %{member_ids: [_ | _]} = errors_on(changeset)
      assert Repo.aggregate(from(c in Conversation, where: c.type == :group), :count) == 0
    end

    test "rejects a non-UUID member id as a validation error" do
      {creator, _} = creator_with_contacts()

      assert {:error, %Ecto.Changeset{} = changeset} =
               Conversations.create_group(creator, "Time", ["not-a-uuid"])

      assert %{member_ids: [_ | _]} = errors_on(changeset)
    end
  end

  describe "get_conversation/2 for a group" do
    test "returns a group to an active member with members preloaded and ordered" do
      creator = insert(:user, username: "creator", name: "Ana")
      zoe = insert(:user, username: "zoe", name: "Zoe")
      alvaro = insert(:user, username: "alvaro", name: "Álvaro")
      for u <- [zoe, alvaro], do: insert(:contact, owner: creator, user: u)

      {:ok, group} = Conversations.create_group(creator, "Time", [zoe.id, alvaro.id])

      assert {:ok, loaded} = Conversations.get_conversation(creator, group.id)
      assert loaded.creator.id == creator.id
      assert Enum.map(loaded.participants, & &1.user.name) == ["Álvaro", "Ana", "Zoe"]
    end

    test "returns :not_found to a non-member" do
      group = insert(:group)
      outsider = insert(:user, username: "outsider")

      assert {:error, :not_found} = Conversations.get_conversation(outsider, group.id)
    end

    test "returns :not_found to a departed member" do
      {creator, [c1, _c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])

      :ok = Conversations.remove_member(creator, group.id, c1.id)

      assert {:error, :not_found} = Conversations.get_conversation(c1, group.id)
    end
  end

  describe "add_members/3" do
    test "seats a new contact and returns the updated group" do
      {creator, [c1, c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])

      assert {:ok, updated} = Conversations.add_members(creator, group.id, [c2.id])
      assert c2.id in MapSet.to_list(active_ids(group.id))
      assert match?([_, _, _], updated.participants)
    end

    test "re-activates a departed member with a fresh joined_at" do
      {creator, [c1, _c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])

      original = Repo.get_by!(Participant, conversation_id: group.id, user_id: c1.id)
      :ok = Conversations.remove_member(creator, group.id, c1.id)

      assert {:ok, _} = Conversations.add_members(creator, group.id, [c1.id])

      reactivated = Repo.get_by!(Participant, conversation_id: group.id, user_id: c1.id)
      assert reactivated.id == original.id
      assert is_nil(reactivated.left_at)
      assert DateTime.compare(reactivated.joined_at, original.joined_at) in [:gt, :eq]
    end

    test "rejects a non-creator" do
      {creator, [c1, c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])
      insert(:contact, owner: c1, user: c2)

      assert {:error, :not_group_creator} = Conversations.add_members(c1, group.id, [c2.id])
    end

    test "rejects an already-active member" do
      {creator, [c1, _c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])

      assert {:error, :already_member} = Conversations.add_members(creator, group.id, [c1.id])
    end

    test "rejects a non-contact" do
      {creator, [c1, _c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])
      stranger = insert(:user, username: "stranger")

      assert {:error, :not_a_contact, _} =
               Conversations.add_members(creator, group.id, [stranger.id])
    end

    test "returns :not_found to an outsider" do
      {creator, [c1, _c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])
      outsider = insert(:user, username: "outsider")

      assert {:error, :not_found} = Conversations.add_members(outsider, group.id, [c1.id])
    end
  end

  describe "remove_member/3" do
    test "sets left_at and drops the member from the active list" do
      {creator, [c1, c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id, c2.id])

      assert :ok = Conversations.remove_member(creator, group.id, c2.id)
      refute Conversations.participant?(group.id, c2.id)
      assert MapSet.equal?(active_ids(group.id), MapSet.new([creator.id, c1.id]))
    end

    test "rejects a non-creator" do
      {creator, [c1, c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id, c2.id])

      assert {:error, :not_group_creator} = Conversations.remove_member(c1, group.id, c2.id)
      assert Conversations.participant?(group.id, c2.id)
    end

    test "rejects the creator targeting themselves" do
      {creator, [c1, _c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])

      assert {:error, :cannot_remove_self} =
               Conversations.remove_member(creator, group.id, creator.id)

      assert Conversations.participant?(group.id, creator.id)
    end

    test "returns :not_found for a non-member target" do
      {creator, [c1, _c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])
      stranger = insert(:user, username: "stranger")

      assert {:error, :not_found} = Conversations.remove_member(creator, group.id, stranger.id)
    end

    test "returns :invalid_id for a non-UUID id" do
      {creator, [c1, _c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])

      assert {:error, :invalid_id} = Conversations.remove_member(creator, group.id, "nope")
    end
  end

  describe "leave/2" do
    test "lets a non-creator member leave" do
      {creator, [c1, _c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])

      assert :ok = Conversations.leave(c1, group.id)
      refute Conversations.participant?(group.id, c1.id)
    end

    test "rejects the creator leaving while other members remain" do
      {creator, [c1, c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id, c2.id])

      assert {:error, :creator_has_members} = Conversations.leave(creator, group.id)
      assert Conversations.participant?(group.id, creator.id)
    end

    test "the sole remaining member leaving deletes the group" do
      {creator, [c1, _c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])

      :ok = Conversations.leave(c1, group.id)
      # The creator is now alone; leaving empties and deletes the group.
      assert :ok = Conversations.leave(creator, group.id)
      refute Repo.get(Conversation, group.id)
    end

    test "rejects a non-member" do
      group = insert(:group)
      outsider = insert(:user, username: "outsider")

      assert {:error, :not_found} = Conversations.leave(outsider, group.id)
    end
  end

  describe "participant?/2 in a group" do
    test "is true only for an active group member" do
      {creator, [c1, c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id, c2.id])
      :ok = Conversations.remove_member(creator, group.id, c2.id)
      outsider = insert(:user, username: "outsider")

      assert Conversations.participant?(group.id, c1.id)
      refute Conversations.participant?(group.id, c2.id)
      refute Conversations.participant?(group.id, outsider.id)
    end

    test "accepts records as well as ids, and a bad id is simply not a member" do
      {creator, [c1, _c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])

      assert Conversations.participant?(group, creator)
      refute Conversations.participant?(group.id, "nope")
    end
  end

  describe "list_conversations/1" do
    test "lists private and group conversations in one response" do
      caller = insert(:user)
      private_pair(caller, insert(:user))
      private_pair(caller, insert(:user))
      group_with(caller)
      group_with(caller)

      entries = inbox(caller)

      assert Enum.count(entries) == 4
      assert Enum.count(entries, &(&1.type == :private)) == 2
      assert Enum.count(entries, &(&1.type == :group)) == 2
    end

    test "resolves the title from the counterpart for private conversations" do
      caller = insert(:user)
      other = insert(:user, name: "Carlos Eduardo")
      private_pair(caller, other)

      [entry] = inbox(caller)

      assert entry.title == "Carlos Eduardo"
      assert entry.counterpart.id == other.id
      assert entry.counterpart.username == other.username
      assert entry.member_count == nil
    end

    test "resolves the title from the group name for groups" do
      caller = insert(:user)
      group = group_with(caller, name: "Time de Produto")
      seat(group, insert(:user))
      seat(group, insert(:user))

      [entry] = inbox(caller)

      assert entry.title == "Time de Produto"
      assert entry.member_count == 3
      assert entry.counterpart == nil
    end

    test "orders by last message timestamp descending" do
      caller = insert(:user)
      a = messaged_pair(caller, ago(300))
      b = messaged_pair(caller, ago(100))
      c = messaged_pair(caller, ago(200))

      ids = caller |> inbox() |> Enum.map(& &1.id)

      assert ids == [b.id, c.id, a.id]
    end

    test "places message-less conversations after those with messages" do
      caller = insert(:user)
      messaged = messaged_pair(caller, ago(3600))
      empty = private_pair(caller, insert(:user), joined_at: ago(60))

      ids = caller |> inbox() |> Enum.map(& &1.id)

      assert ids == [messaged.id, empty.id]
    end

    test "orders message-less conversations by their own creation time" do
      caller = insert(:user)
      older = insert(:conversation, participant_key: pair_key(caller, insert(:user)))
      seat(older, caller)
      newer = insert(:conversation, participant_key: pair_key(caller, insert(:user)))
      seat(newer, caller)

      ids = caller |> inbox() |> Enum.map(& &1.id)

      assert ids == [newer.id, older.id]
    end

    test "previews the newest message of each conversation" do
      caller = insert(:user)
      other = insert(:user)
      conv = private_pair(caller, other)

      for n <- 1..9,
          do: insert(:message, conversation: conv, sender: other, inserted_at: ago(1000 - n * 10))

      newest =
        insert(:message,
          conversation: conv,
          sender: other,
          body: "the newest one",
          inserted_at: ago(10)
        )

      [entry] = inbox(caller)

      assert entry.last_message.id == newest.id
      assert entry.last_message.body == "the newest one"
      assert entry.last_message.sender_id == other.id
      assert entry.last_message.inserted_at == newest.inserted_at
    end

    test "breaks a timestamp tie on message id" do
      caller = insert(:user)
      other = insert(:user)
      conv = private_pair(caller, other)
      tie = ago(30)

      ids =
        for _ <- 1..2 do
          insert(:message, conversation: conv, sender: other, inserted_at: tie).id
        end

      expected = Enum.max(ids)

      for _ <- 1..3 do
        [entry] = inbox(caller)
        assert entry.last_message.id == expected
      end
    end

    test "returns a null last_message for a conversation never used" do
      caller = insert(:user)
      group_with(caller)

      [entry] = inbox(caller)

      assert entry.last_message == nil
      assert entry.unread_count == 0
    end

    test "excludes the caller's own messages from the unread count" do
      caller = insert(:user)
      other = insert(:user)
      conv = private_pair(caller, other)

      for _ <- 1..5,
          do: insert(:message, conversation: conv, sender: caller, inserted_at: ago(20))

      for _ <- 1..3, do: insert(:message, conversation: conv, sender: other, inserted_at: ago(10))

      [entry] = inbox(caller)

      assert entry.unread_count == 3
    end

    test "counts every message the caller did not send when last_read_at is null" do
      caller = insert(:user)
      other = insert(:user)
      conv = private_pair(caller, other, last_read_at: nil)

      for _ <- 1..4, do: insert(:message, conversation: conv, sender: other, inserted_at: ago(10))

      [entry] = inbox(caller)

      assert entry.unread_count == 4
    end

    test "counts only messages after last_read_at" do
      caller = insert(:user)
      other = insert(:user)
      marker = ago(100)
      conv = private_pair(caller, other, last_read_at: marker)

      for _ <- 1..3,
          do: insert(:message, conversation: conv, sender: other, inserted_at: ago(200))

      for _ <- 1..2, do: insert(:message, conversation: conv, sender: other, inserted_at: ago(50))

      [entry] = inbox(caller)

      assert entry.unread_count == 2
    end

    test "caps the unread count at 99 and flags the overflow" do
      caller = insert(:user)
      other = insert(:user)
      conv = private_pair(caller, other)
      seed_unread(conv, other, 150)

      [entry] = inbox(caller)

      assert entry.unread_count == 99
      assert entry.unread_overflow == true
    end

    test "reports 99 without overflow at exactly 99 unread" do
      caller = insert(:user)
      other = insert(:user)
      conv = private_pair(caller, other)
      seed_unread(conv, other, 99)

      [entry] = inbox(caller)

      assert entry.unread_count == 99
      assert entry.unread_overflow == false
    end

    test "flags overflow at exactly 100 unread" do
      caller = insert(:user)
      other = insert(:user)
      conv = private_pair(caller, other)
      seed_unread(conv, other, 100)

      [entry] = inbox(caller)

      assert entry.unread_count == 99
      assert entry.unread_overflow == true
    end

    test "counts only messages sent while the caller was an active member" do
      caller = insert(:user)
      group = group_with(caller, joined_at: ago(100))
      other = insert(:user)
      seat(group, other)

      for _ <- 1..2,
          do: insert(:message, conversation: group, sender: other, inserted_at: ago(200))

      for _ <- 1..3,
          do: insert(:message, conversation: group, sender: other, inserted_at: ago(50))

      [entry] = inbox(caller)

      assert entry.unread_count == 3
    end

    test "restarts the unread window after a re-add" do
      caller = insert(:user)
      group = group_with(caller, joined_at: ago(30))
      other = insert(:user)
      seat(group, other)

      for _ <- 1..4,
          do: insert(:message, conversation: group, sender: other, inserted_at: ago(90))

      for _ <- 1..2,
          do: insert(:message, conversation: group, sender: other, inserted_at: ago(10))

      [entry] = inbox(caller)

      assert entry.unread_count == 2
    end

    test "omits a conversation the caller has left" do
      caller = insert(:user)
      group = group_with(caller, name: "Gone")
      other = insert(:user)
      seat(group, other)
      insert(:message, conversation: group, sender: other, inserted_at: ago(10))

      Repo.update_all(
        from(p in Participant, where: p.conversation_id == ^group.id and p.user_id == ^caller.id),
        set: [left_at: ago(5)]
      )

      assert inbox(caller) == []
    end

    test "omits a conversation the caller was never in" do
      caller = insert(:user)
      strangers = private_pair(insert(:user), insert(:user))
      insert(:message, conversation: strangers, sender: insert(:user), inserted_at: ago(10))

      assert inbox(caller) == []
    end

    test "caps the response at 200 conversations" do
      caller = insert(:user)

      for n <- 1..205 do
        conv = private_pair(caller, insert(:user))
        insert(:message, conversation: conv, sender: insert(:user), inserted_at: ago(1000 - n))
      end

      assert Enum.count(inbox(caller)) == 200
    end

    test "issues exactly one query regardless of conversation count" do
      caller = insert(:user)
      for _ <- 1..5, do: messaged_pair(caller, ago(10))
      assert count_queries(fn -> Conversations.list_conversations(caller) end) == 1

      other = insert(:user)
      for _ <- 1..50, do: messaged_pair(other, ago(10))
      assert count_queries(fn -> Conversations.list_conversations(other) end) == 1
    end
  end

  describe "mark_read/2" do
    test "sets the marker for an active participant" do
      caller = insert(:user)
      conv = private_pair(caller, insert(:user), last_read_at: nil)

      assert {:ok, %{conversation_id: id, last_read_at: %DateTime{} = t}} =
               Conversations.mark_read(caller, conv.id)

      assert id == conv.id
      row = Repo.get_by(Participant, conversation_id: conv.id, user_id: caller.id)
      assert row.last_read_at == t
    end

    test "zeroes the unread count on the next list" do
      caller = insert(:user)
      other = insert(:user)
      conv = private_pair(caller, other)
      for _ <- 1..3, do: insert(:message, conversation: conv, sender: other, inserted_at: ago(10))

      {:ok, _} = Conversations.mark_read(caller, conv.id)

      assert [%{unread_count: 0}] = inbox(caller)
      assert [%{unread_count: 0}] = inbox(caller)
    end

    test "is idempotent" do
      caller = insert(:user)
      conv = private_pair(caller, insert(:user))

      assert {:ok, %{last_read_at: first}} = Conversations.mark_read(caller, conv.id)
      assert {:ok, %{last_read_at: second}} = Conversations.mark_read(caller, conv.id)
      assert DateTime.compare(second, first) != :lt
    end

    test "never moves the marker backwards" do
      caller = insert(:user)
      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      conv = private_pair(caller, insert(:user), last_read_at: future)

      assert {:ok, %{last_read_at: ^future}} = Conversations.mark_read(caller, conv.id)
    end

    test "refuses a departed member and writes nothing" do
      caller = insert(:user)
      group = group_with(caller, last_read_at: ago(100))
      left_at = ago(5)

      Repo.update_all(
        from(p in Participant, where: p.conversation_id == ^group.id and p.user_id == ^caller.id),
        set: [left_at: left_at]
      )

      before =
        Repo.get_by(Participant, conversation_id: group.id, user_id: caller.id).last_read_at

      assert {:error, :not_a_participant} = Conversations.mark_read(caller, group.id)
      after_row = Repo.get_by(Participant, conversation_id: group.id, user_id: caller.id)
      assert after_row.last_read_at == before
    end

    test "refuses a non-participant" do
      caller = insert(:user)
      strangers = private_pair(insert(:user), insert(:user))

      assert {:error, :not_found} = Conversations.mark_read(caller, strangers.id)
    end

    test "refuses an unknown conversation" do
      caller = insert(:user)
      assert {:error, :not_found} = Conversations.mark_read(caller, Ecto.UUID.generate())
    end

    test "rejects a malformed id" do
      caller = insert(:user)
      assert {:error, :invalid_id} = Conversations.mark_read(caller, "nope")
    end
  end

  defp ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)

  # The entries of one page, for the assertions that are about the entries and
  # not about the paging around them.
  defp inbox(caller, opts \\ %{}) do
    %{conversations: conversations} = Conversations.list_conversations(caller, opts)
    conversations
  end

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
    creator = opts[:creator] || caller

    group =
      insert(:conversation,
        type: :group,
        name: opts[:name] || "Grupo #{System.unique_integer([:positive])}",
        creator: creator
      )

    seat(group, caller,
      joined_at: opts[:joined_at] || ago(3600),
      last_read_at: opts[:last_read_at]
    )

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

  defp member(conversation, user, joined_at) do
    %Participant{conversation_id: conversation.id, user_id: user.id}
    |> Participant.changeset(%{joined_at: joined_at})
  end

  describe "participant_ids/1" do
    test "returns both members of a private conversation" do
      a = insert(:user, username: "pia", name: "Pia")
      b = insert(:user, username: "pib", name: "Pib")
      conversation = private_conversation(a, b)

      assert MapSet.equal?(
               MapSet.new(Conversations.participant_ids(conversation.id)),
               MapSet.new([a.id, b.id])
             )
    end

    test "excludes departed group members" do
      {creator, [c1, c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id, c2.id])
      :ok = Conversations.remove_member(creator, group.id, c2.id)

      ids = Conversations.participant_ids(group.id)

      assert MapSet.equal?(MapSet.new(ids), MapSet.new([creator.id, c1.id]))
      refute c2.id in ids
    end

    test "accepts a conversation record as well as an id" do
      {creator, [c1]} = creator_with_contacts(1)
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])

      assert MapSet.equal?(
               MapSet.new(Conversations.participant_ids(group)),
               MapSet.new([creator.id, c1.id])
             )
    end

    test "returns an empty list for an unknown conversation" do
      assert Conversations.participant_ids(Ecto.UUID.generate()) == []
    end

    test "returns an empty list for a malformed id" do
      assert Conversations.participant_ids("nope") == []
    end
  end
end
