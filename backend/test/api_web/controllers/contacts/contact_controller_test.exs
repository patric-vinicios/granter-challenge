defmodule ApiWeb.Contacts.ContactControllerTest do
  use ApiWeb.ConnCase, async: true

  alias Api.Accounts.Guardian
  alias Api.Contacts.Contact
  alias Api.Repo

  setup do
    ana = insert(:user, username: "anabeatriz", name: "Ana Beatriz")

    {:ok, conn: authenticate(json_conn(), ana), user: ana}
  end

  describe "POST /api/contacts" do
    test "returns 201 with the contact and its user", %{conn: conn} do
      carlos = insert(:user, username: "carlos", name: "Carlos Silva")

      conn = post(conn, ~p"/api/contacts", %{"username" => "carlos"})

      assert %{"contact" => contact} = json_response(conn, 201)
      assert contact["id"]

      assert contact["user"] == %{
               "id" => carlos.id,
               "username" => "carlos",
               "name" => "Carlos Silva",
               "last_seen_at" => nil
             }
    end

    test "resolves a leading @ and a bare username identically", %{conn: conn} do
      carlos = insert(:user, username: "carlos")
      bruno = insert(:user, username: "bruno")

      bare = post(conn, ~p"/api/contacts", %{"username" => "carlos"})
      decorated = post(conn, ~p"/api/contacts", %{"username" => "@BRUNO"})

      assert json_response(bare, 201)["contact"]["user"]["id"] == carlos.id
      assert json_response(decorated, 201)["contact"]["user"]["id"] == bruno.id
    end

    test "returns 404 user_not_found naming the username", %{conn: conn} do
      conn = post(conn, ~p"/api/contacts", %{"username" => "@Fulano123"})

      assert %{"code" => "user_not_found", "detail" => detail} =
               json_response(conn, 404)["errors"]

      assert detail =~ "@fulano123"
    end

    test "returns 409 on a duplicate and creates no second row", %{conn: conn} do
      insert(:user, username: "carlos")

      assert json_response(post(conn, ~p"/api/contacts", %{"username" => "carlos"}), 201)

      conn = post(conn, ~p"/api/contacts", %{"username" => "carlos"})

      assert json_response(conn, 409)["errors"]["code"] == "contact_already_exists"
      assert Repo.aggregate(Contact, :count) == 1
    end

    test "returns 422 self_contact when adding oneself", %{conn: conn} do
      conn = post(conn, ~p"/api/contacts", %{"username" => "@anabeatriz"})

      assert %{"code" => "self_contact"} = errors = json_response(conn, 422)["errors"]
      refute Map.has_key?(errors, "fields")
      assert Repo.aggregate(Contact, :count) == 0
    end

    test "returns 422 validation_error when username is absent", %{conn: conn} do
      for body <- [%{}, %{"username" => ""}, %{"username" => "   "}] do
        conn = post(conn, ~p"/api/contacts", body)

        assert %{"code" => "validation_error", "fields" => fields} =
                 json_response(conn, 422)["errors"]

        assert fields["username"] == ["can't be blank"]
      end

      assert Repo.aggregate(Contact, :count) == 0
    end

    test "creates no row in the target's list", %{conn: conn} do
      carlos = insert(:user, username: "carlos")

      assert json_response(post(conn, ~p"/api/contacts", %{"username" => "carlos"}), 201)

      carlos_conn = get(authenticate(json_conn(), carlos), ~p"/api/contacts")

      assert json_response(carlos_conn, 200)["contacts"] == []
    end
  end

  describe "GET /api/contacts" do
    test "returns only the caller's contacts, sorted", %{conn: conn, user: ana} do
      for name <- ["zoe", "Bruno", "Ángela", "ana", "Álvaro"] do
        insert(:contact, owner: ana, user: build(:user, name: name))
      end

      insert(:contact, owner: insert(:user), user: build(:user, name: "Alheio"))

      assert %{"contacts" => contacts} = json_response(get(conn, ~p"/api/contacts"), 200)

      assert Enum.map(contacts, & &1["user"]["name"]) == [
               "Álvaro",
               "ana",
               "Ángela",
               "Bruno",
               "zoe"
             ]
    end

    test "returns an empty array for a new user", %{conn: conn} do
      assert json_response(get(conn, ~p"/api/contacts"), 200)["contacts"] == []
    end
  end

  describe "GET /api/contacts?q=" do
    setup %{user: ana} do
      for {name, username} <- [
            {"Ana Paula", "anapaula"},
            {"Bruno Álvares", "brunoalvares"},
            {"Mariana Alves", "mariana_alves"}
          ] do
        insert(:contact, owner: ana, user: build(:user, name: name, username: username))
      end

      :ok
    end

    test "narrows the list to the matching contacts", %{conn: conn} do
      assert %{"contacts" => contacts} = json_response(get(conn, ~p"/api/contacts?q=ana"), 200)

      assert Enum.map(contacts, & &1["user"]["name"]) == ["Ana Paula", "Mariana Alves"]
    end

    test "matches a username accent- and case-insensitively", %{conn: conn} do
      assert %{"contacts" => [contact]} =
               json_response(get(conn, ~p"/api/contacts?q=ALVARES"), 200)

      assert contact["user"]["name"] == "Bruno Álvares"
    end

    test "returns an empty array when nothing matches", %{conn: conn} do
      assert json_response(get(conn, ~p"/api/contacts?q=zzzznada"), 200)["contacts"] == []
    end

    test "treats a blank term as no filter", %{conn: conn} do
      assert %{"contacts" => contacts} = json_response(get(conn, ~p"/api/contacts?q=  "), 200)
      assert Enum.count(contacts) == 3
    end

    test "pages through a filtered list with the cursor it was handed", %{conn: conn} do
      assert %{"contacts" => first, "next_cursor" => cursor, "has_more" => true} =
               json_response(get(conn, ~p"/api/contacts?q=a&limit=2"), 200)

      assert Enum.map(first, & &1["user"]["name"]) == ["Ana Paula", "Bruno Álvares"]
      assert is_binary(cursor)

      assert %{"contacts" => second, "next_cursor" => nil, "has_more" => false} =
               json_response(get(conn, ~p"/api/contacts?q=a&limit=2&cursor=#{cursor}"), 200)

      assert Enum.map(second, & &1["user"]["name"]) == ["Mariana Alves"]
    end
  end

  describe "GET /api/contacts pagination" do
    test "reports no next page when the last one is exactly full", %{conn: conn, user: ana} do
      for name <- ["Ana Paula", "Bruno Alves"] do
        insert(:contact, owner: ana, user: build(:user, name: name))
      end

      assert %{"has_more" => false, "next_cursor" => nil} =
               json_response(get(conn, ~p"/api/contacts?limit=2"), 200)
    end

    test "rejects a limit outside the accepted range", %{conn: conn} do
      assert %{"errors" => %{"fields" => %{"limit" => [message]}}} =
               json_response(get(conn, ~p"/api/contacts?limit=0"), 422)

      assert message =~ "between 1 and 200"

      assert %{"errors" => %{"fields" => %{"limit" => _}}} =
               json_response(get(conn, ~p"/api/contacts?limit=abc"), 422)
    end

    test "rejects a malformed cursor", %{conn: conn} do
      assert json_response(get(conn, ~p"/api/contacts?cursor=nope"), 400)["errors"]["code"] ==
               "invalid_cursor"
    end
  end

  describe "DELETE /api/contacts/:id" do
    test "returns 204 and removes it from the list", %{conn: conn, user: ana} do
      contact = insert(:contact, owner: ana)

      deleted = delete(conn, ~p"/api/contacts/#{contact.id}")

      assert response(deleted, 204) == ""
      assert json_response(get(conn, ~p"/api/contacts"), 200)["contacts"] == []
    end

    test "returns 404 for another user's contact", %{conn: conn, user: ana} do
      carlos = insert(:user, username: "carlos")
      contact = insert(:contact, owner: ana)

      carlos_conn = delete(authenticate(json_conn(), carlos), ~p"/api/contacts/#{contact.id}")

      assert json_response(carlos_conn, 404)["errors"]["code"] == "not_found"
      assert [remaining] = json_response(get(conn, ~p"/api/contacts"), 200)["contacts"]
      assert remaining["id"] == contact.id
    end

    test "returns 404 for a repeated delete", %{conn: conn, user: ana} do
      contact = insert(:contact, owner: ana)

      assert response(delete(conn, ~p"/api/contacts/#{contact.id}"), 204)

      assert json_response(delete(conn, ~p"/api/contacts/#{contact.id}"), 404)["errors"]["code"] ==
               "not_found"
    end

    test "returns 400 invalid_id for a non-UUID id", %{conn: conn} do
      conn = delete(conn, ~p"/api/contacts/not-a-uuid")

      assert json_response(conn, 400)["errors"] == %{
               "code" => "invalid_id",
               "detail" => "The provided id is not a valid identifier"
             }
    end

    test "distinguishes a malformed id from a hidden one", %{conn: conn} do
      hidden = insert(:contact, owner: insert(:user))

      assert json_response(delete(conn, ~p"/api/contacts/not-a-uuid"), 400)["errors"]["code"] ==
               "invalid_id"

      assert json_response(delete(conn, ~p"/api/contacts/#{hidden.id}"), 404)["errors"]["code"] ==
               "not_found"

      assert Repo.get(Contact, hidden.id)
    end
  end

  describe "authentication" do
    test "every contact route requires a valid token", %{user: ana} do
      contact = insert(:contact, owner: ana)

      {:ok, forged, _claims} =
        Guardian.encode_and_sign(ana, %{}, secret: "another-secret-entirely-000000000")

      for conn <- [json_conn(), put_req_header(json_conn(), "authorization", "Bearer #{forged}")] do
        assert json_response(post(conn, ~p"/api/contacts", %{"username" => "carlos"}), 401)[
                 "errors"
               ]["code"] == "unauthenticated"

        assert json_response(get(conn, ~p"/api/contacts"), 401)["errors"]["code"] ==
                 "unauthenticated"

        assert json_response(delete(conn, ~p"/api/contacts/#{contact.id}"), 401)["errors"]["code"] ==
                 "unauthenticated"
      end

      assert Repo.get(Contact, contact.id)
    end
  end

  describe "cross-feature integration" do
    test "a registered user is resolvable by the username registration returned" do
      registration =
        post(json_conn(), ~p"/api/auth/register", %{
          "username" => "carlos",
          "name" => "Carlos Silva",
          "password" => "senha123456"
        })

      assert %{"user" => registered, "token" => _token} = json_response(registration, 201)

      caller = insert(:user, username: "outra")

      added =
        post(authenticate(json_conn(), caller), ~p"/api/contacts", %{
          "username" => registered["username"]
        })

      assert %{"user" => contacted} = json_response(added, 201)["contact"]
      assert contacted["id"] == registered["id"]
      assert contacted["name"] == registered["name"]
    end
  end

  describe "credential leakage" do
    test "no contact response exposes a password hash", %{conn: conn, user: ana} do
      carlos = insert(:user, username: "carlos")

      created = post(conn, ~p"/api/contacts", %{"username" => "carlos"})
      listed = get(conn, ~p"/api/contacts")

      for response <- [created, listed] do
        refute response.resp_body =~ "hashed_password"
        refute response.resp_body =~ "password"
        refute response.resp_body =~ carlos.hashed_password
        refute response.resp_body =~ ana.hashed_password
      end
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _expires_at} = Guardian.issue_token(user)

    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
