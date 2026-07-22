defmodule Api.Accounts.GuardianTest do
  use Api.DataCase, async: true

  alias Api.Accounts.Guardian
  alias Api.Accounts.User

  @seven_days 7 * 24 * 60 * 60

  describe "issue_token/1" do
    test "issues a token whose sub is the user id and exp is 7 days ahead" do
      user = insert(:user)

      assert {:ok, token, %DateTime{} = expires_at} = Guardian.issue_token(user)
      assert {:ok, claims} = Guardian.decode_and_verify(token)

      assert claims["sub"] == user.id
      assert claims["iss"] == "api"
      assert claims["jti"]
      assert claims["iat"]
      assert_in_delta claims["exp"] - claims["iat"], @seven_days, 1
      assert_in_delta DateTime.to_unix(expires_at), claims["exp"], 1
    end

    test "signs with HS256, the algorithm the published contract names" do
      assert {:ok, token, _expires_at} = Guardian.issue_token(insert(:user))

      assert %{"alg" => "HS256"} =
               token
               |> String.split(".")
               |> hd()
               |> Base.url_decode64!(padding: false)
               |> Jason.decode!()
    end
  end

  describe "verification" do
    test "verifies a token it issued and resolves the resource" do
      user = insert(:user)

      assert {:ok, token, _expires_at} = Guardian.issue_token(user)
      assert {:ok, claims} = Guardian.decode_and_verify(token)
      assert {:ok, %User{id: id}} = Guardian.resource_from_claims(claims)
      assert id == user.id
    end

    test "rejects a token signed with a different secret" do
      user = insert(:user)

      {:ok, forged, _claims} =
        Guardian.encode_and_sign(user, %{}, secret: "another-secret-entirely-000000000")

      assert {:error, _reason} = Guardian.decode_and_verify(forged)
    end

    test "rejects an expired token with a distinguishable reason" do
      user = insert(:user)

      {:ok, token, _claims} = Guardian.encode_and_sign(user, %{}, ttl: {-1, :hour})

      assert {:error, :token_expired} = Guardian.decode_and_verify(token)
    end

    test "resolving a token whose subject was deleted returns an error" do
      user = insert(:user)
      {:ok, token, _expires_at} = Guardian.issue_token(user)
      {:ok, claims} = Guardian.decode_and_verify(token)

      Repo.delete!(user)

      assert {:error, :resource_not_found} = Guardian.resource_from_claims(claims)
    end

    test "rejects claims without a subject" do
      assert {:error, :invalid_claims} = Guardian.resource_from_claims(%{})
    end
  end

  describe "subject_for_token/2" do
    test "returns the user id and refuses anything else" do
      user = insert(:user)

      assert Guardian.subject_for_token(user, %{}) == {:ok, user.id}
      assert Guardian.subject_for_token(%{not: :a_user}, %{}) == {:error, :invalid_resource}
    end
  end
end
