defmodule ApiWeb.CORSTest do
  use ApiWeb.ConnCase, async: false

  @vite_origin "http://localhost:5173"

  defp preflight(conn, origin, opts \\ []) do
    conn
    |> put_req_header("origin", origin)
    |> put_req_header("access-control-request-method", Keyword.get(opts, :method, "POST"))
    |> put_req_header(
      "access-control-request-headers",
      Keyword.get(opts, :headers, "authorization,content-type")
    )
    |> options("/api/health")
  end

  defp header(conn, name) do
    conn |> get_resp_header(name) |> List.first() |> to_string()
  end

  describe "preflight" do
    test "an allowed origin gets back the methods and headers the SPA needs", %{conn: conn} do
      conn = preflight(conn, @vite_origin)

      assert conn.status == 204
      assert header(conn, "access-control-allow-origin") == @vite_origin

      allowed_methods = header(conn, "access-control-allow-methods")

      for method <- ~w(GET POST PATCH DELETE) do
        assert allowed_methods =~ method
      end

      assert header(conn, "access-control-allow-headers") =~ "authorization"
      assert header(conn, "access-control-allow-headers") =~ "content-type"
    end

    test "an unlisted origin is not echoed back", %{conn: conn} do
      conn = preflight(conn, "http://evil.test")

      refute header(conn, "access-control-allow-origin") == "http://evil.test"
    end

    test "runs before the route is resolved, so it works on any path", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", @vite_origin)
        |> put_req_header("access-control-request-method", "POST")
        |> options("/api/anything")

      assert conn.status == 204
      assert header(conn, "access-control-allow-origin") == @vite_origin
    end
  end

  describe "CORS_ORIGINS configuration" do
    setup do
      original = Application.get_env(:api, :cors_origins)
      on_exit(fn -> Application.put_env(:api, :cors_origins, original) end)

      :ok
    end

    test "a configured origin is allowed and the previous default is not", %{conn: conn} do
      Application.put_env(:api, :cors_origins, ["https://app.example.com"])

      allowed = preflight(build_conn(), "https://app.example.com")
      assert header(allowed, "access-control-allow-origin") == "https://app.example.com"

      rejected = preflight(conn, @vite_origin)
      refute header(rejected, "access-control-allow-origin") == @vite_origin
    end

    test "the WebSocket origin callback uses the same allowlist" do
      Application.put_env(:api, :cors_origins, ["https://app.example.com"])

      assert ApiWeb.Endpoint.cors_origins(%URI{
               scheme: "https",
               host: "app.example.com",
               port: 443
             })

      refute ApiWeb.Endpoint.cors_origins(%URI{
               scheme: "http",
               host: "localhost",
               port: 5173
             })
    end
  end

  describe "actual requests" do
    test "a simple GET from an allowed origin carries the CORS header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", @vite_origin)
        |> get(~p"/api/health")

      assert conn.status == 200
      assert header(conn, "access-control-allow-origin") == @vite_origin
    end
  end
end
