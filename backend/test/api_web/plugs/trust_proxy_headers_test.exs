defmodule ApiWeb.Plugs.TrustProxyHeadersTest do
  use ExUnit.Case, async: false

  import Plug.Test, only: [conn: 3]

  alias ApiWeb.Plugs.TrustProxyHeaders

  setup do
    previous = Application.get_env(:api, :trust_proxy_headers, false)
    on_exit(fn -> Application.put_env(:api, :trust_proxy_headers, previous) end)
  end

  defp call(headers) do
    Enum.reduce(headers, conn(:get, "/api/health", nil), fn {name, value}, conn ->
      Plug.Conn.put_req_header(conn, name, value)
    end)
    |> TrustProxyHeaders.call(TrustProxyHeaders.init([]))
  end

  describe "when proxy headers are not trusted" do
    setup do
      Application.put_env(:api, :trust_proxy_headers, false)
    end

    test "keeps the address the connection actually came from" do
      conn = call([{"x-forwarded-for", "203.0.113.9"}])

      assert conn.remote_ip == {127, 0, 0, 1}
    end

    test "a client cannot claim an address to get its own throttle bucket" do
      refute call([{"x-forwarded-for", "8.8.8.8"}]).remote_ip == {8, 8, 8, 8}
    end
  end

  describe "when proxy headers are trusted" do
    setup do
      Application.put_env(:api, :trust_proxy_headers, true)
    end

    test "takes the client address from x-forwarded-for" do
      assert call([{"x-forwarded-for", "203.0.113.9"}]).remote_ip == {203, 0, 113, 9}
    end

    test "takes the leftmost entry, the one the outermost proxy accepted" do
      conn = call([{"x-forwarded-for", "203.0.113.9, 70.41.3.18, 150.172.238.178"}])

      assert conn.remote_ip == {203, 0, 113, 9}
    end

    test "reads IPv6 too" do
      assert call([{"x-forwarded-for", "2001:db8::1"}]).remote_ip ==
               {8193, 3512, 0, 0, 0, 0, 0, 1}
    end

    test "falls back to the connection when the header is absent or unparseable" do
      assert call([]).remote_ip == {127, 0, 0, 1}
      assert call([{"x-forwarded-for", "not-an-address"}]).remote_ip == {127, 0, 0, 1}
    end
  end
end
