defmodule Api.ConversationsTest do
  use Api.DataCase, async: true

  import Ecto.Query

  alias Api.Conversations
  alias Api.Conversations.Conversation
  alias Api.Conversations.ConversationParticipant

  # A creator with two contacts, the common starting point for a group.
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
    ConversationParticipant
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
               from(p in ConversationParticipant, where: p.user_id == ^creator.id),
               :count
             ) == 1
    end

    test "de-duplicates repeated member_ids" do
      {creator, [c1, _c2]} = creator_with_contacts()

      assert {:ok, group} = Conversations.create_group(creator, "Time", [c1.id, c1.id])

      assert Repo.aggregate(
               from(p in ConversationParticipant,
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
      assert Repo.aggregate(Conversation, :count) == 0
      assert Repo.aggregate(ConversationParticipant, :count) == 0
    end

    test "rejects an empty member set" do
      {creator, _} = creator_with_contacts()

      assert {:error, %Ecto.Changeset{}} = Conversations.create_group(creator, "Time", [])
      assert Repo.aggregate(Conversation, :count) == 0
    end

    test "rejects a member set that is empty after stripping the creator" do
      {creator, _} = creator_with_contacts()

      assert {:error, %Ecto.Changeset{} = changeset} =
               Conversations.create_group(creator, "Time", [creator.id])

      assert %{member_ids: [_ | _]} = errors_on(changeset)
      assert Repo.aggregate(Conversation, :count) == 0
    end

    test "rejects a name outside 1..60" do
      {creator, [c1, _c2]} = creator_with_contacts()

      for name <- ["", String.duplicate("a", 61)] do
        assert {:error, %Ecto.Changeset{} = changeset} =
                 Conversations.create_group(creator, name, [c1.id])

        assert %{name: [_ | _]} = errors_on(changeset)
      end

      assert Repo.aggregate(Conversation, :count) == 0
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
      assert Repo.aggregate(Conversation, :count) == 0
    end

    test "rejects a non-UUID member id as a validation error" do
      {creator, _} = creator_with_contacts()

      assert {:error, %Ecto.Changeset{} = changeset} =
               Conversations.create_group(creator, "Time", ["not-a-uuid"])

      assert %{member_ids: [_ | _]} = errors_on(changeset)
    end
  end

  describe "get_for_user/2" do
    test "returns a group to an active member with members preloaded and ordered" do
      creator = insert(:user, username: "creator", name: "Ana")
      zoe = insert(:user, username: "zoe", name: "Zoe")
      alvaro = insert(:user, username: "alvaro", name: "Álvaro")
      for u <- [zoe, alvaro], do: insert(:contact, owner: creator, user: u)

      {:ok, group} = Conversations.create_group(creator, "Time", [zoe.id, alvaro.id])

      assert {:ok, loaded} = Conversations.get_for_user(creator, group.id)
      assert loaded.creator.id == creator.id
      assert Enum.map(loaded.participants, & &1.user.name) == ["Álvaro", "Ana", "Zoe"]
    end

    test "returns :not_found to a non-member" do
      group = insert(:group)
      outsider = insert(:user, username: "outsider")

      assert {:error, :not_found} = Conversations.get_for_user(outsider, group.id)
    end

    test "returns :not_found to a departed member" do
      {creator, [c1, _c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])

      :ok = Conversations.remove_member(creator, group.id, c1.id)

      assert {:error, :not_found} = Conversations.get_for_user(c1, group.id)
    end

    test "returns :invalid_id for a non-UUID id" do
      user = insert(:user)
      assert {:error, :invalid_id} = Conversations.get_for_user(user, "nope")
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

      original = Repo.get_by!(ConversationParticipant, conversation_id: group.id, user_id: c1.id)
      :ok = Conversations.remove_member(creator, group.id, c1.id)

      assert {:ok, _} = Conversations.add_members(creator, group.id, [c1.id])

      reactivated =
        Repo.get_by!(ConversationParticipant, conversation_id: group.id, user_id: c1.id)

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
      refute Conversations.active_participant?(group.id, c2.id)
      assert MapSet.equal?(active_ids(group.id), MapSet.new([creator.id, c1.id]))
    end

    test "rejects a non-creator" do
      {creator, [c1, c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id, c2.id])

      assert {:error, :not_group_creator} = Conversations.remove_member(c1, group.id, c2.id)
      assert Conversations.active_participant?(group.id, c2.id)
    end

    test "rejects the creator targeting themselves" do
      {creator, [c1, _c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])

      assert {:error, :cannot_remove_self} =
               Conversations.remove_member(creator, group.id, creator.id)

      assert Conversations.active_participant?(group.id, creator.id)
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
      refute Conversations.active_participant?(group.id, c1.id)
    end

    test "lets the creator leave while others remain, keeping creator_id" do
      {creator, [c1, c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id, c2.id])

      assert :ok = Conversations.leave(creator, group.id)

      reloaded = Repo.get!(Conversation, group.id)
      assert reloaded.creator_id == creator.id
      # Once the creator has left, no further membership change succeeds.
      assert {:error, :not_found} = Conversations.add_members(creator, group.id, [c1.id])
    end

    test "rejects the last active member" do
      {creator, [c1, _c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])

      :ok = Conversations.leave(c1, group.id)

      assert {:error, :last_member} = Conversations.leave(creator, group.id)
      assert Conversations.active_participant?(group.id, creator.id)
    end

    test "rejects a non-member" do
      group = insert(:group)
      outsider = insert(:user, username: "outsider")

      assert {:error, :not_found} = Conversations.leave(outsider, group.id)
    end
  end

  describe "active_participant?/2" do
    test "is true only for an active member" do
      {creator, [c1, c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id, c2.id])
      :ok = Conversations.remove_member(creator, group.id, c2.id)
      outsider = insert(:user, username: "outsider")

      assert Conversations.active_participant?(group.id, c1.id)
      refute Conversations.active_participant?(group.id, c2.id)
      refute Conversations.active_participant?(group.id, outsider.id)
    end

    test "accepts records as well as ids, and a bad id is simply not a member" do
      {creator, [c1, _c2]} = creator_with_contacts()
      {:ok, group} = Conversations.create_group(creator, "Time", [c1.id])

      assert Conversations.active_participant?(group, creator)
      refute Conversations.active_participant?(group.id, "nope")
    end
  end
end
