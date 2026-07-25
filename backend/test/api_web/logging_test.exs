defmodule ApiWeb.LoggingTest do
  use ApiWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Api.Accounts.Guardian
  alias Api.Factory

  setup do
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)

    {:ok, conn: json_conn()}
  end

  describe "authentication events" do
    test "a rejected password logs the attempt and never the password", %{conn: conn} do
      user = insert(:user)

      log =
        capture_log(fn ->
          conn
          |> post(~p"/api/auth/login", %{"username" => user.username, "password" => "wrong-one"})
          |> json_response(401)
        end)

      assert log =~ "event=login_failed username=#{user.username}"
      refute log =~ "wrong-one"
      refute log =~ Factory.valid_password()
    end

    test "a successful login names the actor and leaks no token", %{conn: conn} do
      user = insert(:user)

      {response, log} =
        with_log(fn ->
          conn
          |> post(~p"/api/auth/login", %{
            "username" => user.username,
            "password" => Factory.valid_password()
          })
          |> json_response(200)
        end)

      assert log =~ "event=login_succeeded user_id=#{user.id}"
      refute log =~ response["token"]
      refute log =~ Factory.valid_password()
    end

    test "registration is logged as an audit event", %{conn: conn} do
      log =
        capture_log(fn ->
          conn
          |> post(~p"/api/auth/register", %{
            "username" => "novaconta",
            "name" => "Nova Conta",
            "password" => Factory.valid_password()
          })
          |> json_response(201)
        end)

      assert log =~ "event=account_registered"
      assert log =~ "username=novaconta"
      refute log =~ Factory.valid_password()
    end

    test "a refused token logs the reason behind the 401", %{conn: conn} do
      log =
        capture_log(fn ->
          conn
          |> put_req_header("authorization", "Bearer not-a-jwt")
          |> get(~p"/api/auth/me")
          |> json_response(401)
        end)

      assert log =~ "event=token_rejected reason=unauthenticated"
    end
  end

  describe "request correlation" do
    test "an authenticated request carries user_id in its metadata", %{conn: conn} do
      user = insert(:user)

      {:ok, token, _expires_at} = Guardian.issue_token(user)

      log =
        capture_log(fn ->
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> get(~p"/api/auth/me")
          |> json_response(200)
        end)

      assert log =~ "user_id=#{user.id}"
    end
  end

  describe "health probe noise" do
    test "is demoted below the production level", %{conn: conn} do
      log = capture_log(fn -> conn |> get(~p"/api/health") |> json_response(200) end)

      refute log =~ "GET /api/health"
    end

    test "still shows up when the level is raised", %{conn: conn} do
      Logger.configure(level: :debug)

      log = capture_log(fn -> conn |> get(~p"/api/health") |> json_response(200) end)

      assert log =~ "GET /api/health"
    end

    test "every other route stays logged", %{conn: conn} do
      log = capture_log(fn -> conn |> get(~p"/api/nope") |> json_response(404) end)

      assert log =~ "GET /api/nope"
    end
  end
end
