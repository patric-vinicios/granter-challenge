defmodule ApiWeb.ErrorEnvelopeTest do
  @moduledoc """
  Exercises the endpoint-level failure paths through the real pipeline, rather
  than by calling the renderer, because the thing being guaranteed is that a
  client never receives HTML from this API.
  """

  use ApiWeb.ConnCase, async: true

  describe "unmatched routes" do
    test "an unknown /api path returns the 404 envelope as JSON", %{conn: conn} do
      conn = get(conn, "/api/does-not-exist")

      assert json_response(conn, 404) == %{
               "errors" => %{
                 "code" => "not_found",
                 "detail" => "The requested resource was not found"
               }
             }

      assert content_type(conn) =~ "application/json"
    end

    test "an unknown non-api path also returns JSON, never a Phoenix HTML page", %{conn: conn} do
      conn = get(conn, "/")

      assert json_response(conn, 404)["errors"]["code"] == "not_found"
      assert content_type(conn) =~ "application/json"
      refute conn.resp_body =~ "<html"
    end

    test "a miss answers with JSON even when the client asks for HTML", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept", "text/html")
        |> get("/definitely/not/here")

      assert json_response(conn, 404)["errors"]["code"] == "not_found"
      refute conn.resp_body =~ "<html"
    end

    test "every HTTP method on an unmatched path returns the envelope" do
      for method <- [:get, :post, :patch, :delete] do
        conn = dispatch(build_conn(), @endpoint, method, "/api/nope", nil)

        assert json_response(conn, 404)["errors"]["code"] == "not_found"
      end
    end
  end

  describe "malformed requests" do
    # These paths raise inside the endpoint, and ConnTest re-raises rather
    # than returning the conn, so the rendered response is captured with
    # assert_error_sent -- which is what a real client would receive.
    test "an unparseable JSON body returns 400 malformed_request" do
      {400, headers, body} =
        assert_error_sent(400, fn -> post(json_conn(), "/api/health", "{invalid") end)

      assert Jason.decode!(body) == %{
               "errors" => %{
                 "code" => "malformed_request",
                 "detail" => "The request body is not valid JSON"
               }
             }

      assert content_type(headers) =~ "application/json"
    end

    test "an unsupported content type returns 415" do
      {415, headers, body} =
        assert_error_sent(415, fn ->
          build_conn()
          |> put_req_header("content-type", "text/plain")
          |> post("/api/health", "plain text")
        end)

      assert Jason.decode!(body)["errors"]["code"] == "unsupported_media_type"
      assert content_type(headers) =~ "application/json"
    end

    test "the parser exception never reaches the response body" do
      {400, _headers, body} =
        assert_error_sent(400, fn -> post(json_conn(), "/api/health", "{invalid") end)

      refute body =~ "ParseError"
      refute body =~ "stacktrace"
      refute body =~ "__exception__"
      refute body =~ "Jason.DecodeError"
    end
  end

  describe "envelope shape" do
    test "every non-2xx response carries a code and a detail, and no fields outside 422" do
      bodies = [
        get(build_conn(), "/api/does-not-exist").resp_body,
        elem(assert_error_sent(400, fn -> post(json_conn(), "/api/health", "{invalid") end), 2),
        elem(
          assert_error_sent(415, fn ->
            build_conn()
            |> put_req_header("content-type", "text/plain")
            |> post("/api/health", "nope")
          end),
          2
        )
      ]

      for body <- bodies do
        assert %{"errors" => errors} = Jason.decode!(body)
        assert match?(<<_, _::binary>>, errors["code"])
        assert match?(<<_, _::binary>>, errors["detail"])
        refute Map.has_key?(errors, "fields")
      end
    end
  end

  defp content_type(%Plug.Conn{} = conn) do
    conn |> get_resp_header("content-type") |> content_type()
  end

  defp content_type(headers) when is_list(headers) do
    headers
    |> Enum.find_value(fn
      {"content-type", value} -> value
      value when is_binary(value) -> value
      _other -> nil
    end)
    |> to_string()
  end
end
