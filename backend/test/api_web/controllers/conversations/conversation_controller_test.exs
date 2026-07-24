defmodule ApiWeb.Conversations.ConversationControllerTest do
  use ApiWeb.ConnCase, async: true

  alias Api.Accounts.Guardian
  alias Api.Conversations.Conversation
  alias Api.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    ana = insert(:user, username: "anabeatriz", name: "Ana Beatriz")
    carlos = insert(:user, username: "carlos", name: "Carlos Silva")
    insert(:contact, owner: ana, user: carlos)

    {:ok, conn: authenticate(json_conn(), ana), ana: ana, carlos: carlos}
  end

  describe "POST /api/conversations/private" do
    test "returns 201 with the conversation and its counterpart", %{conn: conn, carlos: carlos} do
      conn = post(conn, ~p"/api/conversations/private", %{"user_id" => carlos.id})

      assert %{"conversation" => conversation} = json_response(conn, 201)
      assert conversation["id"]
      assert conversation["type"] == "private"
      assert conversation["last_read_at"] == nil

      assert conversation["counterpart"] == %{
               "id" => carlos.id,
               "username" => "carlos",
               "name" => "Carlos Silva",
               "last_seen_at" => nil,
               "online" => false
             }
    end

    test "returns 200 and the same id on the second call", %{conn: conn, carlos: carlos} do
      first = post(conn, ~p"/api/conversations/private", %{"user_id" => carlos.id})
      id = json_response(first, 201)["conversation"]["id"]

      second = post(conn, ~p"/api/conversations/private", %{"user_id" => carlos.id})

      assert json_response(second, 200)["conversation"]["id"] == id
      assert Repo.aggregate(Conversation, :count) == 1
    end

    test "two concurrent creates yield one conversation and no 500", %{ana: ana, carlos: carlos} do
      parent = self()

      tasks =
        for _ <- 1..2 do
          Task.async(fn ->
            Sandbox.allow(Repo, parent, self())

            post(authenticate(json_conn(), ana), ~p"/api/conversations/private", %{
              "user_id" => carlos.id
            })
          end)
        end

      responses = Task.await_many(tasks)

      assert Enum.all?(responses, &(&1.status in [200, 201]))
      ids = Enum.map(responses, &json_response(&1, &1.status)["conversation"]["id"])
      assert [_single] = Enum.uniq(ids)
      assert Repo.aggregate(Conversation, :count) == 1
    end

    test "returns 403 not_a_contact for a non-contact", %{conn: conn} do
      stranger = insert(:user)

      conn = post(conn, ~p"/api/conversations/private", %{"user_id" => stranger.id})

      assert json_response(conn, 403)["errors"]["code"] == "not_a_contact"
      assert Repo.aggregate(Conversation, :count) == 0
    end

    test "returns 404 user_not_found for an unknown id", %{conn: conn} do
      conn = post(conn, ~p"/api/conversations/private", %{"user_id" => Ecto.UUID.generate()})

      assert json_response(conn, 404)["errors"]["code"] == "user_not_found"
    end

    test "returns 422 self_conversation for one's own id", %{conn: conn, ana: ana} do
      conn = post(conn, ~p"/api/conversations/private", %{"user_id" => ana.id})

      assert %{"code" => "self_conversation"} = errors = json_response(conn, 422)["errors"]
      refute Map.has_key?(errors, "fields")
      assert Repo.aggregate(Conversation, :count) == 0
    end

    test "returns 422 validation_error when user_id is absent", %{conn: conn} do
      conn = post(conn, ~p"/api/conversations/private", %{})

      assert %{"code" => "validation_error", "fields" => fields} =
               json_response(conn, 422)["errors"]

      assert fields["user_id"]
    end
  end

  describe "GET /api/conversations/:id" do
    test "the recipient reads the conversation without the initiator as a contact", %{
      conn: conn,
      ana: ana,
      carlos: carlos
    } do
      created = post(conn, ~p"/api/conversations/private", %{"user_id" => carlos.id})
      id = json_response(created, 201)["conversation"]["id"]

      # Carlos never added Ana back, yet reads the thread and sees Ana as the counterpart.
      carlos_conn = get(authenticate(json_conn(), carlos), ~p"/api/conversations/#{id}")

      assert %{"conversation" => conversation} = json_response(carlos_conn, 200)
      assert conversation["counterpart"]["id"] == ana.id
      assert conversation["counterpart"]["username"] == "anabeatriz"
    end

    test "reports an offline counterpart as online:false with its last_seen_at", %{
      conn: conn,
      carlos: carlos
    } do
      created = post(conn, ~p"/api/conversations/private", %{"user_id" => carlos.id})
      id = json_response(created, 201)["conversation"]["id"]

      conn = get(conn, ~p"/api/conversations/#{id}")

      assert %{"conversation" => conversation} = json_response(conn, 200)
      assert conversation["counterpart"]["online"] == false
      assert conversation["counterpart"]["last_seen_at"] == nil
    end

    test "carries a per-member online flag in a group detail", %{
      conn: conn,
      ana: ana,
      carlos: carlos
    } do
      {:ok, group} = Api.Conversations.create_group(ana, "Time", [carlos.id])

      conn = get(conn, ~p"/api/conversations/#{group.id}")

      assert %{"conversation" => %{"type" => "group", "members" => members}} =
               json_response(conn, 200)

      assert [_, _] = members
      assert Enum.all?(members, &(&1["online"] == false))
      assert Enum.all?(members, &Map.has_key?(&1, "last_seen_at"))
    end

    test "returns 404 for a non-participant", %{conn: conn, carlos: carlos} do
      created = post(conn, ~p"/api/conversations/private", %{"user_id" => carlos.id})
      id = json_response(created, 201)["conversation"]["id"]

      outsider = insert(:user)
      outsider_conn = get(authenticate(json_conn(), outsider), ~p"/api/conversations/#{id}")

      assert json_response(outsider_conn, 404)["errors"]["code"] == "not_found"
      refute outsider_conn.resp_body =~ "counterpart"
    end

    test "returns 400 invalid_id for a non-UUID id", %{conn: conn} do
      conn = get(conn, ~p"/api/conversations/not-a-uuid")

      assert json_response(conn, 400)["errors"]["code"] == "invalid_id"
    end
  end

  describe "contact lifecycle across conversations" do
    test "stays readable after the contact is removed, but a new create is refused", %{ana: ana} do
      ana_conn = authenticate(json_conn(), ana)

      registration =
        post(json_conn(), ~p"/api/auth/register", %{
          "username" => "diego",
          "name" => "Diego Ramos",
          "password" => "senha123456"
        })

      diego = json_response(registration, 201)["user"]

      added = post(ana_conn, ~p"/api/contacts", %{"username" => diego["username"]})
      assert json_response(added, 201)

      created = post(ana_conn, ~p"/api/conversations/private", %{"user_id" => diego["id"]})
      conversation_id = json_response(created, 201)["conversation"]["id"]

      contact_id = json_response(added, 201)["contact"]["id"]
      assert response(delete(ana_conn, ~p"/api/contacts/#{contact_id}"), 204)

      # The existing thread still reads...
      still_readable = get(ana_conn, ~p"/api/conversations/#{conversation_id}")
      assert json_response(still_readable, 200)["conversation"]["id"] == conversation_id

      # ...but a fresh create is now refused.
      refused = post(ana_conn, ~p"/api/conversations/private", %{"user_id" => diego["id"]})
      assert json_response(refused, 403)["errors"]["code"] == "not_a_contact"
      assert Repo.aggregate(Conversation, :count) == 1
    end
  end

  describe "authentication and leakage" do
    test "both routes require authentication", %{ana: ana, carlos: carlos} do
      no_token = json_conn()
      forged = put_req_header(json_conn(), "authorization", "Bearer not-a-real-token")

      for conn <- [no_token, forged] do
        create = post(conn, ~p"/api/conversations/private", %{"user_id" => carlos.id})
        assert json_response(create, 401)["errors"]["code"] == "unauthenticated"

        show = get(conn, ~p"/api/conversations/#{Ecto.UUID.generate()}")
        assert json_response(show, 401)["errors"]["code"] == "unauthenticated"
      end

      assert Repo.aggregate(Conversation, :count) == 0
      # A well-formed token for a real user proves the fixtures are otherwise valid.
      assert {:ok, _token, _} = Guardian.issue_token(ana)
    end

    test "no conversation response exposes a password hash", %{
      conn: conn,
      ana: ana,
      carlos: carlos
    } do
      created = post(conn, ~p"/api/conversations/private", %{"user_id" => carlos.id})
      id = json_response(created, 201)["conversation"]["id"]
      shown = get(conn, ~p"/api/conversations/#{id}")

      for response <- [created, shown] do
        refute response.resp_body =~ "hashed_password"
        refute response.resp_body =~ "password"
        refute response.resp_body =~ ana.hashed_password
        refute response.resp_body =~ carlos.hashed_password
      end
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _expires_at} = Guardian.issue_token(user)

    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
