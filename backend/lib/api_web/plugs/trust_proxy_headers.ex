defmodule ApiWeb.Plugs.TrustProxyHeaders do
  @moduledoc """
  Takes `conn.remote_ip` from `x-forwarded-for` when the deployment says that
  header can be trusted.

  Behind a reverse proxy every request arrives from the proxy's address, and two
  things quietly break: `ApiWeb.LoginThrottle`'s per-IP ceiling stops being
  per-IP and becomes one shared bucket for the whole internet, and every
  `login_failed` line in the log names the proxy instead of the client.

  It is off by default and enabled with `TRUST_PROXY_HEADERS=true`, because the
  header is only as trustworthy as whoever set it. Reaching this endpoint
  directly, a client could send its own `x-forwarded-for` and get a private
  throttle bucket per forged address — which is why this must stay off until a
  proxy that *overwrites* the header sits in front of every request. The value
  used is the leftmost entry, the one such a proxy fills in with the client it
  accepted the connection from.
  """

  @behaviour Plug

  @impl Plug
  def init(_opts), do: Plug.RewriteOn.init([:x_forwarded_for])

  @impl Plug
  def call(conn, rewrite) do
    if Application.get_env(:api, :trust_proxy_headers, false) do
      Plug.RewriteOn.call(conn, rewrite)
    else
      conn
    end
  end
end
