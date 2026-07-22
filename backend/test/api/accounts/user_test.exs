defmodule Api.Accounts.UserTest do
  use Api.DataCase, async: true

  alias Api.Accounts.User

  @valid_attrs %{
    "username" => "anabeatriz",
    "name" => "Ana Beatriz",
    "password" => "senha123456"
  }

  defp changeset(overrides \\ %{}) do
    User.registration_changeset(%User{}, Map.merge(@valid_attrs, overrides))
  end

  describe "registration_changeset/2" do
    test "accepts a valid username, name and password" do
      changeset = changeset()

      assert changeset.valid?
      assert changeset.changes.hashed_password
      refute Map.has_key?(changeset.changes, :password)
    end

    test "strips the display @ from the username" do
      assert changeset(%{"username" => "  @anabeatriz "}).changes.username == "anabeatriz"
    end

    test "requires every field" do
      changeset = User.registration_changeset(%User{}, %{})

      refute changeset.valid?
      assert %{username: _, name: _, password: _} = errors_on(changeset)
    end

    test "rejects usernames with uppercase, spaces or invalid characters" do
      for username <- ["Ana", "ana beatriz", "ana-beatriz", "ana!"] do
        changeset = changeset(%{"username" => username})

        refute changeset.valid?, "expected #{inspect(username)} to be rejected"
        assert errors_on(changeset).username != []
      end
    end

    test "rejects usernames shorter than 3 or longer than 20 characters" do
      assert changeset(%{"username" => String.duplicate("a", 3)}).valid?
      assert changeset(%{"username" => String.duplicate("a", 20)}).valid?
      refute changeset(%{"username" => String.duplicate("a", 2)}).valid?
      refute changeset(%{"username" => String.duplicate("a", 21)}).valid?
    end

    test "rejects names outside 2-60 characters and trims whitespace" do
      assert changeset(%{"name" => "  Ana  "}).changes.name == "Ana"
      assert changeset(%{"name" => String.duplicate("a", 60)}).valid?
      refute changeset(%{"name" => "a"}).valid?
      refute changeset(%{"name" => String.duplicate("a", 61)}).valid?
    end

    test "rejects passwords shorter than 8 or longer than 72 characters" do
      assert changeset(%{"password" => String.duplicate("a", 8)}).valid?
      assert changeset(%{"password" => String.duplicate("a", 72)}).valid?
      refute changeset(%{"password" => String.duplicate("a", 7)}).valid?
      refute changeset(%{"password" => String.duplicate("a", 73)}).valid?
    end

    test "the stored hash is not the plaintext and verifies against it" do
      hash = changeset().changes.hashed_password

      refute hash == @valid_attrs["password"]
      assert Argon2.verify_pass(@valid_attrs["password"], hash)
    end

    test "an invalid changeset never hashes anything" do
      changeset = changeset(%{"username" => "no"})

      refute changeset.valid?
      refute Map.has_key?(changeset.changes, :hashed_password)
    end
  end

  describe "normalize_username/1" do
    test "strips the display @ and downcases for lookups" do
      assert User.normalize_username(" @AnaBeatriz ") == "anabeatriz"
    end

    test "leaves a value it cannot normalise untouched" do
      assert User.normalize_username(nil) == nil
      assert User.normalize_username(42) == 42
    end
  end

  describe "credential redaction" do
    test "inspecting a user does not reveal the hash" do
      user = insert(:user)

      refute inspect(user) =~ user.hashed_password
      assert inspect(user) =~ user.username
    end

    test "inspecting a changeset does not reveal the plaintext" do
      refute inspect(changeset()) =~ @valid_attrs["password"]
    end
  end
end
