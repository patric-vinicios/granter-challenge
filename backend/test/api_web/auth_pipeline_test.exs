defmodule ApiWeb.AuthPipelineTest do
  use ApiWeb.ConnCase, async: true

  alias Api.Accounts.Guardian
  alias Api.Repo
  alias ApiWeb.FallbackController

  # /api/auth/me is the only route behind the pipeline for now; every route
  # from the contacts feature onward inherits exactly this behaviour.
  defp protected, do: ~p"/api/auth/me"

  defp authenticated(user) do
    {:ok, token, _expires_at} = Guardian.issue_token(user)

    put_req_header(json_conn(), "authorization", "Bearer #{token}")
  end

  test "a valid token assigns current_user and lets the action run" do
    user = insert(:user)

    conn = get(authenticated(user), protected())

    assert conn.status == 200
    assert conn.assigns.current_user.id == user.id
    refute conn.halted
  end

  test "a malformed Authorization header is rejected before the action", %{conn: conn} do
    for header <- ["Token abc", "Bearer", "", "Basic dXNlcjpwYXNz"] do
      conn =
        conn
        |> recycle()
        |> put_req_header("authorization", header)
        |> get(protected())

      assert json_response(conn, 401)["errors"]["code"] == "unauthenticated",
             "expected #{inspect(header)} to be rejected"

      assert conn.halted
      refute conn.assigns[:current_user]
    end
  end

  test "a token for a deleted user is rejected and assigns no user" do
    user = insert(:user)
    conn = authenticated(user)

    Repo.delete!(user)

    conn = get(conn, protected())

    assert json_response(conn, 401)["errors"]["code"] == "unauthenticated"
    refute conn.assigns[:current_user]
  end

  describe "ApiWeb.AuthErrorHandler" do
    test "maps every Guardian expiry shape to token_expired and the rest to unauthenticated",
         %{conn: conn} do
      expired = [{:invalid_token, :token_expired}, {:invalid_token, "token_expired"}]
      generic = [{:unauthenticated, :unauthenticated}, {:invalid_token, :invalid_signature}]

      for {error, code} <-
            Enum.map(expired, &{&1, "token_expired"}) ++
              Enum.map(generic, &{&1, "unauthenticated"}) do
        result =
          ApiWeb.AuthErrorHandler.auth_error(
            Phoenix.Controller.put_format(conn, "json"),
            error,
            []
          )

        assert result.status == 401
        assert Jason.decode!(result.resp_body)["errors"]["code"] == code
      end
    end
  end

  test "the pipeline's 401 body is identical to a FallbackController 401", %{conn: conn} do
    from_pipeline = conn |> get(protected()) |> json_response(401)

    from_fallback =
      build_conn()
      |> Phoenix.Controller.put_format("json")
      |> Plug.Conn.put_private(:phoenix_endpoint, ApiWeb.Endpoint)
      |> FallbackController.call({:error, :unauthenticated})
      |> Map.fetch!(:resp_body)
      |> Jason.decode!()

    assert from_pipeline == from_fallback
  end
end
