defmodule ApiWeb.HealthControllerTest do
  use ApiWeb.ConnCase, async: true

  import ExUnit.CaptureLog, only: [with_log: 1]

  alias Ecto.Adapters.SQL.Sandbox

  describe "GET /api/health" do
    test "returns 200 and reports the database up when it is reachable", %{conn: conn} do
      conn = get(conn, ~p"/api/health")

      assert json_response(conn, 200) == %{"status" => "ok", "database" => "up"}
    end

    test "requires no authentication", %{conn: conn} do
      refute get_req_header(conn, "authorization") != []

      conn = get(conn, ~p"/api/health")

      assert conn.status == 200
    end

    @tag :capture_log
    test "returns 503 with the database_unavailable envelope when the database is gone", %{
      conn: conn,
      sandbox_owner: owner
    } do
      # Dropping the sandbox owner leaves the probe with no connection to run
      # its SELECT 1 on, which is the closest a test gets to a dead database.
      Sandbox.stop_owner(owner)

      conn = get(conn, ~p"/api/health")
      body = json_response(conn, 503)

      assert body["status"] == "error"
      assert body["database"] == "down"
      assert body["errors"]["code"] == "database_unavailable"
      assert body["errors"]["detail"] == "Database connection is not available"
    end

    test "logs the reason it withheld from the body", %{conn: conn, sandbox_owner: owner} do
      Sandbox.stop_owner(owner)

      {_body, log} = with_log(fn -> conn |> get(~p"/api/health") |> json_response(503) end)

      assert log =~ "[error]"
      assert log =~ "event=database_unavailable"
    end

    @tag :capture_log
    test "never leaks connection details in the failure body", %{
      conn: conn,
      sandbox_owner: owner
    } do
      Sandbox.stop_owner(owner)

      body = conn |> get(~p"/api/health") |> json_response(503) |> Jason.encode!()

      refute body =~ "postgres"
      refute body =~ "password"
      refute body =~ "54321"
    end
  end
end
