defmodule ApiWeb.Accounts.AuthControllerTest do
  use ApiWeb.ConnCase, async: true

  alias Api.Accounts.Guardian
  alias Api.Accounts.User
  alias Api.Repo

  @valid_attrs %{
    "username" => "anabeatriz",
    "name" => "Ana Beatriz",
    "password" => "senha123456"
  }

  setup do
    {:ok, conn: json_conn()}
  end

  describe "POST /api/auth/register" do
    test "returns 201 with the user, a token and expires_at", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/register", @valid_attrs)

      assert %{"user" => user, "token" => token, "expires_at" => expires_at} =
               json_response(conn, 201)

      assert user["id"]
      assert user["username"] == "anabeatriz"
      assert user["name"] == "Ana Beatriz"
      assert user["last_seen_at"] == nil
      assert is_binary(token) and token != ""

      assert {:ok, expires_at, 0} = DateTime.from_iso8601(expires_at)
      assert_in_delta DateTime.diff(expires_at, DateTime.utc_now()), 7 * 24 * 60 * 60, 60
    end

    test "accepts a leading @ and stores the bare username", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/register", %{@valid_attrs | "username" => "@anabeatriz"})

      assert json_response(conn, 201)["user"]["username"] == "anabeatriz"
    end

    test "returns 422 with fields.username for an existing username", %{conn: conn} do
      insert(:user, username: "anabeatriz")

      conn = post(conn, ~p"/api/auth/register", @valid_attrs)

      assert %{"code" => "validation_error", "fields" => fields} =
               json_response(conn, 422)["errors"]

      assert fields["username"] == ["has already been taken"]
    end

    test "treats an existing username case-insensitively", %{conn: conn} do
      insert(:user, username: "AnaBeatriz")

      conn = post(conn, ~p"/api/auth/register", @valid_attrs)

      assert json_response(conn, 422)["errors"]["fields"]["username"] == [
               "has already been taken"
             ]
    end

    test "rejects an uppercase username outright", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/register", %{@valid_attrs | "username" => "AnaBeatriz"})

      assert json_response(conn, 422)["errors"]["fields"]["username"]
      assert Repo.aggregate(User, :count) == 0
    end

    test "rejects uppercase, spaced and too-short usernames and creates nothing", %{conn: conn} do
      for username <- ["AnaBeatriz", "ana beatriz", "an", "ana!"] do
        conn = post(conn, ~p"/api/auth/register", %{@valid_attrs | "username" => username})

        assert json_response(conn, 422)["errors"]["fields"]["username"],
               "expected #{inspect(username)} to be rejected"
      end

      assert Repo.aggregate(User, :count) == 0
    end

    test "rejects a missing body with 422 rather than a 500", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/register", %{})

      assert %{"code" => "validation_error", "fields" => fields} =
               json_response(conn, 422)["errors"]

      assert fields["username"] && fields["name"] && fields["password"]
    end
  end

  describe "POST /api/auth/login" do
    setup do
      %{user: insert(:user, username: "anabeatriz")}
    end

    test "returns 200 with a token whose sub is the user id", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/api/auth/login", %{
          "username" => "anabeatriz",
          "password" => valid_password()
        })

      assert %{"user" => rendered, "token" => token} = json_response(conn, 200)
      assert rendered["id"] == user.id

      assert {:ok, claims} = Guardian.decode_and_verify(token)
      assert claims["sub"] == user.id
      assert_in_delta claims["exp"] - claims["iat"], 7 * 24 * 60 * 60, 1
    end

    test "matches the username case-insensitively and with a leading @", %{conn: conn} do
      for username <- ["AnaBeatriz", "@anabeatriz"] do
        conn =
          post(conn, ~p"/api/auth/login", %{
            "username" => username,
            "password" => valid_password()
          })

        assert json_response(conn, 200)["token"]
      end
    end

    test "a wrong password and an unknown username return the identical body", %{conn: conn} do
      wrong =
        conn
        |> post(~p"/api/auth/login", %{"username" => "anabeatriz", "password" => "wrong-one!!"})
        |> json_response(401)

      unknown =
        json_conn()
        |> post(~p"/api/auth/login", %{"username" => "ghost", "password" => "wrong-one!!"})
        |> json_response(401)

      assert wrong == unknown

      assert wrong == %{
               "errors" => %{
                 "code" => "invalid_credentials",
                 "detail" => "Invalid username or password"
               }
             }
    end

    test "a missing password is a 422 naming the field, not a failed login", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/login", %{"username" => "anabeatriz"})

      assert json_response(conn, 422)["errors"]["fields"]["password"] == ["can't be blank"]
    end
  end

  describe "GET /api/auth/me" do
    test "returns the authenticated user", %{conn: conn} do
      user = insert(:user)
      {:ok, token, _expires_at} = Guardian.issue_token(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/auth/me")

      assert json_response(conn, 200)["user"]["id"] == user.id
    end

    test "returns 401 unauthenticated without a token", %{conn: conn} do
      conn = get(conn, ~p"/api/auth/me")

      assert json_response(conn, 401)["errors"]["code"] == "unauthenticated"
    end

    test "returns 401 for a token signed by another secret", %{conn: conn} do
      user = insert(:user)

      {:ok, forged, _claims} =
        Guardian.encode_and_sign(user, %{}, secret: "another-secret-entirely-000000000")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{forged}")
        |> get(~p"/api/auth/me")

      assert json_response(conn, 401)["errors"]["code"] == "unauthenticated"
      refute conn.assigns[:current_user]
    end

    test "returns 401 token_expired for an expired token", %{conn: conn} do
      {:ok, token, _claims} = Guardian.encode_and_sign(insert(:user), %{}, ttl: {-1, :hour})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/auth/me")

      assert json_response(conn, 401)["errors"]["code"] == "token_expired"
    end
  end

  describe "DELETE /api/auth/session (logout)" do
    test "revokes the token so the same one is rejected afterwards", %{conn: conn} do
      {:ok, token, _} = Guardian.issue_token(insert(:user))

      assert response(
               delete(
                 put_req_header(conn, "authorization", "Bearer #{token}"),
                 ~p"/api/auth/session"
               ),
               204
             )

      reused =
        json_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/auth/me")

      assert json_response(reused, 401)["errors"]["code"] == "unauthenticated"
    end

    test "requires a token", %{conn: conn} do
      assert json_response(delete(conn, ~p"/api/auth/session"), 401)
    end
  end

  describe "credential leakage" do
    test "no auth response body contains a password or a hash", %{conn: conn} do
      register = post(conn, ~p"/api/auth/register", @valid_attrs)
      assert %{"token" => token} = json_response(register, 201)

      login =
        post(json_conn(), ~p"/api/auth/login", %{
          "username" => "anabeatriz",
          "password" => @valid_attrs["password"]
        })

      me =
        json_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/auth/me")

      user = Repo.get_by!(User, username: "anabeatriz")

      for conn <- [register, login, me] do
        body = conn.resp_body

        refute body =~ "hashed_password"
        refute body =~ "password"
        refute body =~ user.hashed_password
        refute body =~ @valid_attrs["password"]
      end
    end
  end
end
