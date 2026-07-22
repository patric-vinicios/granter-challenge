defmodule ApiWeb.ConversationGroupControllerTest do
  use ApiWeb.ConnCase, async: true

  alias Api.Accounts.Guardian
  alias Api.Conversations.Conversation
  alias Api.Repo

  import Ecto.Query

  setup do
    ana = insert(:user, username: "anabeatriz", name: "Ana Beatriz")
    carlos = insert(:user, username: "carlosedu", name: "Carlos Eduardo")
    joao = insert(:user, username: "joaopedro", name: "João Pedro")

    for u <- [carlos, joao], do: insert(:contact, owner: ana, user: u)

    {:ok, conn: authenticate(json_conn(), ana), ana: ana, carlos: carlos, joao: joao}
  end

  defp groups_count, do: Repo.aggregate(from(c in Conversation, where: c.type == :group), :count)

  # Creates a group owned by `ana` with the given contacts seated, returning its id.
  defp create_group(conn, name, member_ids) do
    conn
    |> post(~p"/api/conversations/groups", %{"name" => name, "member_ids" => member_ids})
    |> json_response(201)
    |> get_in(["conversation", "id"])
  end

  describe "POST /api/conversations/groups" do
    test "returns 201 with 3 members including the creator", %{
      conn: conn,
      ana: ana,
      carlos: carlos,
      joao: joao
    } do
      conn =
        post(conn, ~p"/api/conversations/groups", %{
          "name" => "Time de Produto",
          "member_ids" => [carlos.id, joao.id]
        })

      assert %{"conversation" => group} = json_response(conn, 201)
      assert group["id"]
      assert group["type"] == "group"
      assert group["name"] == "Time de Produto"
      assert group["creator_id"] == ana.id
      assert group["member_count"] == 3

      member_ids = Enum.map(group["members"], & &1["id"])
      assert Enum.sort(member_ids) == Enum.sort([ana.id, carlos.id, joao.id])
      assert Enum.all?(group["members"], &Map.has_key?(&1, "username"))
    end

    test "seats the creator without them in member_ids", %{conn: conn, ana: ana, carlos: carlos} do
      conn =
        post(conn, ~p"/api/conversations/groups", %{
          "name" => "Time",
          "member_ids" => [carlos.id]
        })

      member_ids = json_response(conn, 201)["conversation"]["members"] |> Enum.map(& &1["id"])
      assert ana.id in member_ids
    end

    test "returns 403 not_a_contact naming offenders, creating nothing", %{
      conn: conn,
      carlos: carlos
    } do
      stranger = insert(:user, username: "estranho")

      conn =
        post(conn, ~p"/api/conversations/groups", %{
          "name" => "Time",
          "member_ids" => [carlos.id, stranger.id]
        })

      assert %{"code" => "not_a_contact", "detail" => detail} = json_response(conn, 403)["errors"]
      assert detail =~ "@estranho"
      assert groups_count() == 0
    end

    test "returns 422 for empty member_ids", %{conn: conn} do
      conn =
        post(conn, ~p"/api/conversations/groups", %{"name" => "Time", "member_ids" => []})

      assert json_response(conn, 422)["errors"]["code"] == "validation_error"
      assert groups_count() == 0
    end

    test "returns 422 for a name outside 1..60", %{conn: conn, carlos: carlos} do
      for name <- ["", String.duplicate("a", 61)] do
        conn =
          post(conn, ~p"/api/conversations/groups", %{
            "name" => name,
            "member_ids" => [carlos.id]
          })

        assert %{"code" => "validation_error", "fields" => fields} =
                 json_response(conn, 422)["errors"]

        assert fields["name"]
      end

      assert groups_count() == 0
    end

    test "no endpoint changes a group's name", %{conn: conn, carlos: carlos} do
      id = create_group(conn, "Time de Produto", [carlos.id])

      name = get(conn, ~p"/api/conversations/#{id}") |> json_response(200)
      assert name["conversation"]["name"] == "Time de Produto"
    end
  end

  describe "GET /api/conversations/:id for a group" do
    test "returns the group to a member with ordered members", %{
      conn: conn,
      carlos: carlos,
      joao: joao
    } do
      id = create_group(conn, "Time", [carlos.id, joao.id])

      conn = get(conn, ~p"/api/conversations/#{id}")

      assert %{"conversation" => group} = json_response(conn, 200)
      assert group["member_count"] == 3
      # Ana Beatriz, Carlos Eduardo, João Pedro — accent-folded ascending.
      assert Enum.map(group["members"], & &1["name"]) ==
               ["Ana Beatriz", "Carlos Eduardo", "João Pedro"]
    end

    test "returns 404 to a non-member", %{conn: conn, carlos: carlos} do
      id = create_group(conn, "Time", [carlos.id])
      outsider = insert(:user, username: "outsider")

      conn = get(authenticate(json_conn(), outsider), ~p"/api/conversations/#{id}")

      assert json_response(conn, 404)["errors"]["code"] == "not_found"
    end
  end

  describe "POST /api/conversations/:id/members" do
    test "lets the creator add a contact", %{conn: conn, carlos: carlos, joao: joao} do
      id = create_group(conn, "Time", [carlos.id])

      conn = post(conn, ~p"/api/conversations/#{id}/members", %{"member_ids" => [joao.id]})

      member_ids = json_response(conn, 200)["conversation"]["members"] |> Enum.map(& &1["id"])
      assert joao.id in member_ids
    end

    test "returns 403 not_group_creator for a member", %{conn: conn, carlos: carlos, joao: joao} do
      id = create_group(conn, "Time", [carlos.id])
      insert(:contact, owner: carlos, user: joao)

      conn =
        post(authenticate(json_conn(), carlos), ~p"/api/conversations/#{id}/members", %{
          "member_ids" => [joao.id]
        })

      assert json_response(conn, 403)["errors"]["code"] == "not_group_creator"
    end

    test "returns 409 already_member", %{conn: conn, carlos: carlos} do
      id = create_group(conn, "Time", [carlos.id])

      conn = post(conn, ~p"/api/conversations/#{id}/members", %{"member_ids" => [carlos.id]})

      assert json_response(conn, 409)["errors"]["code"] == "already_member"
    end

    test "re-adds a departed member with a cleared left_at", %{conn: conn, carlos: carlos} do
      id = create_group(conn, "Time", [carlos.id])
      assert response(delete(conn, ~p"/api/conversations/#{id}/members/#{carlos.id}"), 204)

      conn = post(conn, ~p"/api/conversations/#{id}/members", %{"member_ids" => [carlos.id]})

      member_ids = json_response(conn, 200)["conversation"]["members"] |> Enum.map(& &1["id"])
      assert carlos.id in member_ids
    end
  end

  describe "DELETE /api/conversations/:id/members/:user_id" do
    test "removes a member", %{conn: conn, carlos: carlos, joao: joao} do
      id = create_group(conn, "Time", [carlos.id, joao.id])

      assert response(delete(conn, ~p"/api/conversations/#{id}/members/#{joao.id}"), 204) == ""

      members = get(conn, ~p"/api/conversations/#{id}") |> json_response(200)
      member_ids = Enum.map(members["conversation"]["members"], & &1["id"])
      refute joao.id in member_ids
    end

    test "rejects a non-creator", %{conn: conn, carlos: carlos, joao: joao} do
      id = create_group(conn, "Time", [carlos.id, joao.id])

      conn =
        delete(authenticate(json_conn(), carlos), ~p"/api/conversations/#{id}/members/#{joao.id}")

      assert json_response(conn, 403)["errors"]["code"] == "not_group_creator"
    end

    test "rejects the creator's own id", %{conn: conn, ana: ana, carlos: carlos} do
      id = create_group(conn, "Time", [carlos.id])

      conn = delete(conn, ~p"/api/conversations/#{id}/members/#{ana.id}")

      assert json_response(conn, 422)["errors"]["code"] == "cannot_remove_self"
    end
  end

  describe "DELETE /api/conversations/:id/members/me" do
    test "lets a member leave", %{conn: conn, carlos: carlos} do
      id = create_group(conn, "Time", [carlos.id])

      carlos_conn = authenticate(json_conn(), carlos)
      assert response(delete(carlos_conn, ~p"/api/conversations/#{id}/members/me"), 204) == ""

      assert json_response(get(carlos_conn, ~p"/api/conversations/#{id}"), 404)
    end

    test "returns 422 last_member for the sole member", %{conn: conn, carlos: carlos} do
      id = create_group(conn, "Time", [carlos.id])

      assert response(
               delete(authenticate(json_conn(), carlos), ~p"/api/conversations/#{id}/members/me"),
               204
             )

      conn = delete(conn, ~p"/api/conversations/#{id}/members/me")

      assert json_response(conn, 422)["errors"]["code"] == "last_member"
    end
  end

  describe "authentication" do
    test "every group route requires a valid token", %{conn: conn, carlos: carlos} do
      id = create_group(conn, "Time", [carlos.id])
      anon = json_conn()

      assert json_response(post(anon, ~p"/api/conversations/groups", %{}), 401)
      assert json_response(get(anon, ~p"/api/conversations/#{id}"), 401)
      assert json_response(post(anon, ~p"/api/conversations/#{id}/members", %{}), 401)
      assert json_response(delete(anon, ~p"/api/conversations/#{id}/members/me"), 401)
      assert json_response(delete(anon, ~p"/api/conversations/#{id}/members/#{carlos.id}"), 401)
    end
  end

  describe "credential leakage" do
    test "no group response exposes a password hash", %{conn: conn, ana: ana, carlos: carlos} do
      id = create_group(conn, "Time", [carlos.id])

      created =
        post(conn, ~p"/api/conversations/groups", %{
          "name" => "Outro",
          "member_ids" => [carlos.id]
        })

      shown = get(conn, ~p"/api/conversations/#{id}")

      for response <- [created, shown] do
        refute response.resp_body =~ "hashed_password"
        refute response.resp_body =~ "password"
        refute response.resp_body =~ ana.hashed_password
        refute response.resp_body =~ carlos.hashed_password
      end
    end
  end

  describe "cross-feature integration with contacts" do
    test "a contact added through the contacts endpoint is accepted while a non-contact fails" do
      caller = insert(:user, username: "caller", name: "Caller")
      contact = insert(:user, username: "aceito", name: "Aceito")
      stranger = insert(:user, username: "recusado", name: "Recusado")

      conn = authenticate(json_conn(), caller)

      assert json_response(post(conn, ~p"/api/contacts", %{"username" => "aceito"}), 201)

      # A non-contact in the same array fails the whole creation.
      rejected =
        post(conn, ~p"/api/conversations/groups", %{
          "name" => "Time",
          "member_ids" => [contact.id, stranger.id]
        })

      assert %{"code" => "not_a_contact", "detail" => detail} =
               json_response(rejected, 403)["errors"]

      assert detail =~ "@recusado"
      assert groups_count() == 0

      # The contact alone succeeds.
      accepted =
        post(conn, ~p"/api/conversations/groups", %{
          "name" => "Time",
          "member_ids" => [contact.id]
        })

      assert %{"conversation" => group} = json_response(accepted, 201)
      member_ids = Enum.map(group["members"], & &1["id"])
      assert Enum.sort(member_ids) == Enum.sort([caller.id, contact.id])
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _expires_at} = Guardian.issue_token(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
