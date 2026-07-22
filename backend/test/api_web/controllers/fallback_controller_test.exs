defmodule ApiWeb.FallbackControllerTest do
  use ApiWeb.ConnCase, async: true

  alias ApiWeb.FallbackController

  defmodule Sample do
    use Api.Schema

    schema "samples" do
      field :username, :string
    end
  end

  defp conn_for_fallback do
    build_conn()
    |> Phoenix.Controller.put_format("json")
    |> Plug.Conn.put_private(:phoenix_endpoint, ApiWeb.Endpoint)
  end

  defp body(conn), do: Jason.decode!(conn.resp_body)

  describe "call/2 with an error atom" do
    test "translates :not_found to a 404 envelope" do
      conn = FallbackController.call(conn_for_fallback(), {:error, :not_found})

      assert conn.status == 404
      assert body(conn)["errors"]["code"] == "not_found"
    end

    test "translates :unauthorized to 403, which is a different answer from 401" do
      conn = FallbackController.call(conn_for_fallback(), {:error, :unauthorized})

      assert conn.status == 403
      assert body(conn)["errors"]["code"] == "forbidden"
    end

    test "translates :conflict to 409" do
      conn = FallbackController.call(conn_for_fallback(), {:error, :conflict})

      assert conn.status == 409
      assert body(conn)["errors"]["code"] == "conflict"
    end

    test "translates the authentication reasons to 401, each with its own code" do
      for {reason, code} <- [unauthenticated: "unauthenticated", token_expired: "token_expired"] do
        conn = FallbackController.call(conn_for_fallback(), {:error, reason})

        assert conn.status == 401
        assert body(conn)["errors"]["code"] == code
      end
    end

    test "translates :invalid_credentials to 401 with its own code" do
      conn = FallbackController.call(conn_for_fallback(), {:error, :invalid_credentials})

      assert conn.status == 401

      assert body(conn)["errors"] == %{
               "code" => "invalid_credentials",
               "detail" => "Invalid username or password"
             }
    end

    test "translates :rate_limited to 429" do
      conn = FallbackController.call(conn_for_fallback(), {:error, :rate_limited})

      assert conn.status == 429
      assert body(conn)["errors"]["code"] == "rate_limited"
    end

    test "translates the contact reasons to their codes and statuses" do
      reasons = [
        {:invalid_id, 400, "invalid_id"},
        {:user_not_found, 404, "user_not_found"},
        {:contact_already_exists, 409, "contact_already_exists"},
        {:self_contact, 422, "self_contact"},
        {:contact_limit_reached, 422, "contact_limit_reached"}
      ]

      for {reason, status, code} <- reasons do
        conn = FallbackController.call(conn_for_fallback(), {:error, reason})

        assert conn.status == status, "expected #{reason} at #{status}"
        assert body(conn)["errors"]["code"] == code
        assert body(conn)["errors"]["detail"] != ""
      end
    end

    test "invalid_id does not collide with the endpoint-level 400" do
      conn = FallbackController.call(conn_for_fallback(), {:error, :invalid_id})

      # The endpoint answers an unparseable body at the same status through
      # ErrorJSON, so a client can only tell a bad path param from a bad body
      # if the two carry different codes.
      {malformed_request, _detail} = ApiWeb.ErrorJSON.error_for(400)

      assert conn.status == 400
      assert body(conn)["errors"]["code"] == "invalid_id"
      refute body(conn)["errors"]["code"] == malformed_request
    end

    test "a contact reason at 422 carries no fields key" do
      conn = FallbackController.call(conn_for_fallback(), {:error, :self_contact})

      assert conn.status == 422
      assert %{"code" => "self_contact", "detail" => _detail} = body(conn)["errors"]
      refute Map.has_key?(body(conn)["errors"], "fields")
    end

    test "translates the conversation reasons to their codes and statuses" do
      reasons = [
        {:not_a_contact, 403, "not_a_contact"},
        {:self_conversation, 422, "self_conversation"}
      ]

      for {reason, status, code} <- reasons do
        conn = FallbackController.call(conn_for_fallback(), {:error, reason})

        assert conn.status == status, "expected #{reason} at #{status}"
        assert body(conn)["errors"]["code"] == code
        assert body(conn)["errors"]["detail"] != ""
      end
    end

    test "self_conversation at 422 carries no fields key" do
      conn = FallbackController.call(conn_for_fallback(), {:error, :self_conversation})

      assert conn.status == 422
      assert %{"code" => "self_conversation", "detail" => _detail} = body(conn)["errors"]
      refute Map.has_key?(body(conn)["errors"], "fields")
    end

    test "not_a_contact accepts an overriding detail" do
      conn =
        FallbackController.call(
          conn_for_fallback(),
          {:error, :not_a_contact, "These users are not in your contacts: @carlosedu"}
        )

      assert conn.status == 403

      assert body(conn)["errors"] == %{
               "code" => "not_a_contact",
               "detail" => "These users are not in your contacts: @carlosedu"
             }
    end

    test "an unmapped reason becomes a 500 rather than leaking the atom" do
      conn = FallbackController.call(conn_for_fallback(), {:error, :something_unexpected})

      assert conn.status == 500
      assert body(conn)["errors"]["code"] == "internal_error"
      refute conn.resp_body =~ "something_unexpected"
    end
  end

  describe "call/2 with an explicit detail" do
    test "uses the given detail in place of the default message" do
      conn =
        FallbackController.call(
          conn_for_fallback(),
          {:error, :conflict, "You are already a member of this group"}
        )

      assert conn.status == 409

      assert body(conn)["errors"] == %{
               "code" => "conflict",
               "detail" => "You are already a member of this group"
             }
    end

    test "an explicit detail still overrides a contact reason's default" do
      conn =
        FallbackController.call(
          conn_for_fallback(),
          {:error, :user_not_found, "No user with @fulano123 exists in the system"}
        )

      assert conn.status == 404

      assert body(conn)["errors"] == %{
               "code" => "user_not_found",
               "detail" => "No user with @fulano123 exists in the system"
             }
    end

    test "an explicit detail still overrides a reason-table default" do
      conn =
        FallbackController.call(
          conn_for_fallback(),
          {:error, :invalid_credentials, "That account is disabled"}
        )

      assert conn.status == 401

      assert body(conn)["errors"] == %{
               "code" => "invalid_credentials",
               "detail" => "That account is disabled"
             }
    end
  end

  describe "call/2 with the group reasons" do
    test "translates each group reason to its code and status" do
      cases = [
        {:not_a_contact, 403, "not_a_contact"},
        {:not_group_creator, 403, "not_group_creator"},
        {:already_member, 409, "already_member"},
        {:last_member, 422, "last_member"},
        {:cannot_remove_self, 422, "cannot_remove_self"}
      ]

      for {reason, status, code} <- cases do
        conn = FallbackController.call(conn_for_fallback(), {:error, reason})

        assert conn.status == status
        assert body(conn)["errors"]["code"] == code
      end
    end

    test "a group reason at 422 carries no fields key" do
      conn = FallbackController.call(conn_for_fallback(), {:error, :last_member})

      errors = body(conn)["errors"]
      assert Map.has_key?(errors, "code")
      assert Map.has_key?(errors, "detail")
      refute Map.has_key?(errors, "fields")
    end

    test "an interpolated detail overrides not_a_contact's default" do
      conn =
        FallbackController.call(
          conn_for_fallback(),
          {:error, :not_a_contact, "These users are not in your contacts: @joaopedro"}
        )

      assert conn.status == 403

      assert body(conn)["errors"] == %{
               "code" => "not_a_contact",
               "detail" => "These users are not in your contacts: @joaopedro"
             }
    end
  end

  describe "call/2 with a changeset" do
    test "renders 422 with the per-field messages" do
      changeset =
        Sample
        |> struct!()
        |> Ecto.Changeset.cast(%{}, [:username])
        |> Ecto.Changeset.validate_required([:username])

      conn = FallbackController.call(conn_for_fallback(), {:error, changeset})

      assert conn.status == 422
      assert body(conn)["errors"]["code"] == "validation_error"
      assert body(conn)["errors"]["fields"]["username"] == ["can't be blank"]
    end
  end
end
