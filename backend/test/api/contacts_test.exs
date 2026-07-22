defmodule Api.ContactsTest do
  use Api.DataCase, async: true

  alias Api.Accounts.User
  alias Api.Contacts
  alias Api.Contacts.Contact

  describe "add_contact/2" do
    setup do
      %{owner: insert(:user, username: "anabeatriz"), target: insert(:user, username: "carlos")}
    end

    test "resolves a username and persists the pair", %{owner: owner, target: target} do
      assert {:ok, %Contact{} = contact} = Contacts.add_contact(owner, "carlos")

      assert contact.owner_id == owner.id
      assert contact.contact_user_id == target.id
      assert %User{id: id} = contact.user
      assert id == target.id
      assert Repo.get(Contact, contact.id)
    end

    test "resolves case-insensitively and accepts a leading @", %{owner: owner, target: target} do
      for username <- ["carlos", "Carlos", "@carlos", "@CARLOS"] do
        Repo.delete_all(Contact)

        assert {:ok, contact} = Contacts.add_contact(owner, username),
               "expected #{inspect(username)} to resolve"

        assert contact.contact_user_id == target.id
      end
    end

    test "returns :user_not_found for an unknown username", %{owner: owner} do
      assert {:error, :user_not_found, detail} = Contacts.add_contact(owner, "@Fulano123")

      assert detail =~ "@fulano123"
      assert Repo.aggregate(Contact, :count) == 0
    end

    test "truncates an oversized username in the detail", %{owner: owner} do
      oversized = String.duplicate("a", 200)

      assert {:error, :user_not_found, detail} = Contacts.add_contact(owner, oversized)

      refute detail =~ String.duplicate("a", 21)
    end

    test "returns :self_contact when the target is the owner", %{owner: owner} do
      assert {:error, :self_contact} = Contacts.add_contact(owner, "@anabeatriz")
      assert Repo.aggregate(Contact, :count) == 0
    end

    test "returns :contact_already_exists on a second add", %{owner: owner} do
      assert {:ok, _contact} = Contacts.add_contact(owner, "carlos")

      assert {:error, :contact_already_exists, detail} = Contacts.add_contact(owner, "carlos")

      assert detail =~ "@carlos"
      assert Repo.aggregate(Contact, :count) == 1
    end

    test "is unidirectional", %{owner: owner, target: target} do
      assert {:ok, _contact} = Contacts.add_contact(owner, "carlos")

      assert Contacts.list_contacts(target) == []
      refute Repo.exists?(where(Contact, [c], c.owner_id == ^target.id))
    end

    test "returns :contact_limit_reached at the ceiling", %{owner: owner} do
      fill_contact_list(owner, 500)

      assert {:error, :contact_limit_reached, detail} = Contacts.add_contact(owner, "carlos")

      assert detail =~ "500"
      assert Repo.aggregate(Contact, :count) == 500
    end

    test "reports a duplicate ahead of the limit", %{owner: owner, target: target} do
      fill_contact_list(owner, 499)
      insert(:contact, owner: owner, user: target)

      assert {:error, :contact_already_exists, _detail} = Contacts.add_contact(owner, "carlos")
    end
  end

  describe "the database guarantees" do
    test "a duplicate pair inserted through the changeset is a constraint error" do
      owner = insert(:user)
      target = insert(:user)

      assert {:ok, _contact} = insert_contact_pair(owner.id, target.id)

      assert {:error, %Ecto.Changeset{} = changeset} = insert_contact_pair(owner.id, target.id)
      assert errors_on(changeset).owner_id == ["has already been taken"]
      assert Repo.aggregate(Contact, :count) == 1
    end

    test "the database rejects a self-pair written directly" do
      user = insert(:user)

      assert {:error, %Ecto.Changeset{} = changeset} = insert_contact_pair(user.id, user.id)
      assert errors_on(changeset).contact_user_id == ["cannot be the owner"]
      assert Repo.aggregate(Contact, :count) == 0
    end

    test "a pair naming a user that does not exist is a constraint error" do
      owner = insert(:user)

      assert {:error, %Ecto.Changeset{} = changeset} =
               insert_contact_pair(owner.id, Ecto.UUID.generate())

      assert errors_on(changeset).contact_user_id == ["does not exist"]
    end
  end

  describe "list_contacts/1" do
    test "returns only the owner's contacts" do
      owner = insert(:user)
      other = insert(:user)
      mine = insert(:contact, owner: owner)
      theirs = insert(:contact, owner: other)

      assert [contact] = Contacts.list_contacts(owner)
      assert contact.id == mine.id
      refute contact.id == theirs.id
    end

    test "sorts case- and accent-insensitively" do
      owner = insert(:user)

      for name <- ["zoe", "Bruno", "Ángela", "ana", "Álvaro"] do
        insert(:contact, owner: owner, user: build(:user, name: name))
      end

      assert Enum.map(Contacts.list_contacts(owner), & &1.user.name) == [
               "Álvaro",
               "ana",
               "Ángela",
               "Bruno",
               "zoe"
             ]
    end

    test "breaks ties on a stable key" do
      owner = insert(:user)

      for _index <- 1..3 do
        insert(:contact, owner: owner, user: build(:user, name: "Ana Beatriz"))
      end

      ids = Enum.map(Contacts.list_contacts(owner), & &1.id)

      assert ids == Enum.map(Contacts.list_contacts(owner), & &1.id)
      assert [_first, _second, _third] = Enum.uniq(ids)
    end

    test "preloads the contacted user" do
      owner = insert(:user)
      insert(:contact, owner: owner)

      assert [%Contact{user: %User{}}] = Contacts.list_contacts(owner)
    end

    test "returns an empty list for a user with no contacts" do
      assert Contacts.list_contacts(insert(:user)) == []
    end
  end

  describe "delete_contact/2" do
    test "removes the row" do
      owner = insert(:user)
      contact = insert(:contact, owner: owner)

      assert :ok = Contacts.delete_contact(owner, contact.id)

      refute Repo.get(Contact, contact.id)
      assert Contacts.list_contacts(owner) == []
    end

    test "returns :not_found for another user's contact id" do
      owner = insert(:user)
      contact = insert(:contact, owner: owner)

      assert {:error, :not_found} = Contacts.delete_contact(insert(:user), contact.id)
      assert Repo.get(Contact, contact.id)
    end

    test "returns :not_found for an unknown id" do
      assert {:error, :not_found} =
               Contacts.delete_contact(insert(:user), Ecto.UUID.generate())
    end

    test "returns :invalid_id for a value that is not a UUID" do
      owner = insert(:user)

      for id <- ["not-a-uuid", "", String.duplicate("a", 200), "123"] do
        assert {:error, :invalid_id} = Contacts.delete_contact(owner, id),
               "expected #{inspect(id)} to be rejected before the query"
      end
    end

    test "leaves the contacted user's account intact" do
      owner = insert(:user)
      contact = insert(:contact, owner: owner)

      assert :ok = Contacts.delete_contact(owner, contact.id)
      assert Repo.get(User, contact.contact_user_id)
    end
  end

  describe "cascade from users" do
    test "deleting a user cascades to both sides of the contact list" do
      ana = insert(:user)
      carlos = insert(:user)
      bruno = insert(:user)

      insert(:contact, owner: ana, user: carlos)
      insert(:contact, owner: bruno, user: ana)
      untouched = insert(:contact, owner: bruno, user: carlos)

      Repo.delete!(ana)

      assert Repo.aggregate(Contact, :count) == 1
      assert Repo.get(Contact, untouched.id)
      assert Repo.get(User, carlos.id)
      assert Repo.get(User, bruno.id)
    end
  end

  describe "contact?/2" do
    setup do
      ana = insert(:user)
      carlos = insert(:user)
      insert(:contact, owner: ana, user: carlos)

      %{ana: ana, carlos: carlos}
    end

    test "is true only for a persisted pair", %{ana: ana, carlos: carlos} do
      assert Contacts.contact?(ana, carlos)
      refute Contacts.contact?(carlos, ana)
      refute Contacts.contact?(ana, insert(:user))
    end

    test "takes the contacted user as an id as well as a record", %{ana: ana, carlos: carlos} do
      assert Contacts.contact?(ana, carlos.id)
      refute Contacts.contact?(ana, Ecto.UUID.generate())
    end

    test "is false for an id that is not a UUID rather than raising", %{ana: ana} do
      refute Contacts.contact?(ana, "not-a-uuid")
    end
  end

  defp insert_contact_pair(owner_id, contact_user_id) do
    %Contact{owner_id: owner_id, contact_user_id: contact_user_id}
    |> Contact.changeset()
    |> Repo.insert()
  end

  defp fill_contact_list(owner, count) do
    now = DateTime.utc_now()

    users =
      Enum.map(1..count, fn index ->
        %{
          id: Ecto.UUID.generate(),
          username: "filler#{System.unique_integer([:positive])}#{index}",
          name: "Filler #{index}",
          hashed_password: "x",
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(User, users)

    Repo.insert_all(
      Contact,
      Enum.map(users, fn user ->
        %{owner_id: owner.id, contact_user_id: user.id, inserted_at: now}
      end)
    )
  end
end
