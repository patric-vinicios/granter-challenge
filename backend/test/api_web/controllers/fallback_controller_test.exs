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

    test "translates the authentication reasons to 401" do
      for reason <- [:unauthenticated, :token_expired] do
        conn = FallbackController.call(conn_for_fallback(), {:error, reason})

        assert conn.status == 401
        assert body(conn)["errors"]["code"] == "unauthenticated"
      end
    end

    test "translates :rate_limited to 429" do
      conn = FallbackController.call(conn_for_fallback(), {:error, :rate_limited})

      assert conn.status == 429
      assert body(conn)["errors"]["code"] == "rate_limited"
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
