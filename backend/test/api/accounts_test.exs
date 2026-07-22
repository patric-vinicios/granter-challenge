defmodule Api.AccountsTest do
  use Api.DataCase, async: true

  alias Api.Accounts
  alias Api.Accounts.User

  @valid_attrs %{
    "username" => "anabeatriz",
    "name" => "Ana Beatriz",
    "password" => "senha123456"
  }

  describe "register_user/1" do
    test "persists a user and hashes the password" do
      assert {:ok, %User{} = user} = Accounts.register_user(@valid_attrs)

      assert Repo.get(User, user.id)
      assert user.username == "anabeatriz"
      refute user.hashed_password == @valid_attrs["password"]
      assert Argon2.verify_pass(@valid_attrs["password"], user.hashed_password)
    end

    test "rejects a duplicate username case-insensitively" do
      # Inserted around the changeset so the stored value differs in case from
      # the one registered below: uniqueness is the citext column's job.
      insert(:user, username: "AnaBeatriz")

      assert {:error, changeset} = Accounts.register_user(@valid_attrs)

      assert errors_on(changeset).username == ["has already been taken"]
      assert Repo.aggregate(User, :count) == 1
    end

    test "rejects an uppercase username rather than silently downcasing it" do
      assert {:error, changeset} =
               Accounts.register_user(%{@valid_attrs | "username" => "AnaBeatriz"})

      assert errors_on(changeset).username != []
      assert Repo.aggregate(User, :count) == 0
    end

    test "returns a changeset for invalid params without inserting" do
      assert {:error, changeset} = Accounts.register_user(%{})

      refute changeset.valid?
      assert Repo.aggregate(User, :count) == 0
    end
  end

  describe "authenticate/2" do
    setup do
      %{user: insert(:user, username: "anabeatriz")}
    end

    test "returns the user for correct credentials", %{user: user} do
      assert {:ok, %User{id: id}} = Accounts.authenticate("anabeatriz", valid_password())
      assert id == user.id
    end

    test "matches the username case-insensitively", %{user: user} do
      assert {:ok, %User{id: id}} = Accounts.authenticate("AnaBeatriz", valid_password())
      assert id == user.id
    end

    test "accepts a leading @ in the username", %{user: user} do
      assert {:ok, %User{id: id}} = Accounts.authenticate("@anabeatriz", valid_password())
      assert id == user.id
    end

    test "returns the same error for a wrong password and an unknown username" do
      wrong_password = Accounts.authenticate("anabeatriz", "not-the-password")
      unknown_user = Accounts.authenticate("ghost", "not-the-password")

      assert wrong_password == {:error, :invalid_credentials}
      assert unknown_user == wrong_password
    end

    test "rejects non-string credentials rather than raising" do
      assert Accounts.authenticate(nil, nil) == {:error, :invalid_credentials}
    end
  end

  describe "get_user/1" do
    test "returns the user and nil for an unknown id" do
      user = insert(:user)

      assert Accounts.get_user(user.id).id == user.id
      assert Accounts.get_user(Ecto.UUID.generate()) == nil
    end

    test "returns nil for an id that is not a UUID instead of raising" do
      assert Accounts.get_user("not-a-uuid") == nil
      assert Accounts.get_user(42) == nil
    end
  end

  describe "get_user_by_username/1" do
    test "resolves case-insensitively and with a leading @" do
      user = insert(:user, username: "anabeatriz")

      assert Accounts.get_user_by_username("anabeatriz").id == user.id
      assert Accounts.get_user_by_username("AnaBeatriz").id == user.id
      assert Accounts.get_user_by_username("@ANABEATRIZ").id == user.id
    end

    test "returns nil when the username is absent or not a string" do
      assert Accounts.get_user_by_username("ghost") == nil
      assert Accounts.get_user_by_username(nil) == nil
    end
  end
end
